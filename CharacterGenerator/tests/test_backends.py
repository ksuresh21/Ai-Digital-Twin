import base64
import io
from types import SimpleNamespace

from PIL import Image

import character_generator.backends as backends
import pytest


class FakeInteractions:
    def __init__(self, response):
        self.response = response
        self.request = None

    def create(self, **kwargs):
        self.request = kwargs
        return self.response


def test_gemini_uses_interactions_with_prompt_and_reference(reference_image, monkeypatch):
    output = Image.new("RGBA", (40, 30), (10, 20, 30, 255))
    encoded = io.BytesIO()
    output.save(encoded, format="PNG")
    interaction = SimpleNamespace(
        steps=[SimpleNamespace(
            type="model_output",
            content=[
                SimpleNamespace(type="text", text="done"),
                SimpleNamespace(type="image", data=base64.b64encode(encoded.getvalue()).decode()),
            ],
        )],
        usage={"total_tokens": 321},
    )
    fake_interactions = FakeInteractions(interaction)
    fake_client = SimpleNamespace(interactions=fake_interactions)
    monkeypatch.setattr(backends, "_create_gemini_client", lambda api_key: fake_client)

    result = backends.GeminiBackend(api_key="test-key").generate("draw this", reference_image)

    request = fake_interactions.request
    assert request["model"] == "models/gemini-3.1-flash-lite-image"
    assert request["generation_config"] == {
        "temperature": 1,
        "max_output_tokens": 65536,
        "top_p": 0.95,
        "thinking_level": "minimal",
    }
    assert request["response_modalities"] == ["image", "text"]
    assert request["input"][0] == {"type": "text", "text": "draw this"}
    assert base64.b64decode(request["input"][1]["data"]) == reference_image.read_bytes()
    assert request["input"][1]["mime_type"] == "image/png"
    assert result.backend == "gemini"
    assert result.image.size == (40, 30)
    assert result.usage == {"total_tokens": 321}


def test_gemini_429_becomes_batch_stopping_quota_error(reference_image, monkeypatch):
    class QuotaInteractions:
        def create(self, **kwargs):
            raise RuntimeError(
                "Error code: 429 - Quota exceeded, limit: 0. Please retry in 29.1s."
            )

    monkeypatch.setattr(
        backends, "_create_gemini_client",
        lambda api_key: SimpleNamespace(interactions=QuotaInteractions()),
    )
    with pytest.raises(backends.QuotaExceeded) as caught:
        backends.GeminiBackend(api_key="test-key").generate("draw", reference_image)
    assert "HTTP 429" in str(caught.value)
    assert "zero request quota" in str(caught.value)


def test_cloudflare_uses_reference_image_and_decodes_result(reference_image, monkeypatch):
    output = Image.new("RGBA", (40, 30), (10, 20, 30, 255))
    encoded = io.BytesIO()
    output.save(encoded, format="PNG")
    captured = {}

    class Response:
        status_code = 200

        def json(self):
            return {"result": {"image": base64.b64encode(encoded.getvalue()).decode()}}

    def fake_post(url, **kwargs):
        captured.update(url=url, **kwargs)
        return Response()

    monkeypatch.setattr(backends.requests, "post", fake_post)
    result = backends.CloudflareBackend(
        account_id="account", api_token="token", retries=0
    ).generate("draw this", reference_image)

    assert captured["url"].endswith("/@cf/black-forest-labs/flux-2-klein-4b")
    assert captured["headers"] == {"Authorization": "Bearer token"}
    assert captured["data"]["width"] == "1536"
    assert "input image 0" in captured["data"]["prompt"]
    uploaded = Image.open(io.BytesIO(captured["files"]["input_image_0"][1]))
    assert max(uploaded.size) <= 511
    assert result.backend == "cloudflare"
    assert result.image.size == (40, 30)


def test_cloudflare_429_becomes_batch_stopping_quota_error(reference_image, monkeypatch):
    class Response:
        status_code = 429

        def json(self):
            return {"errors": [{"message": "daily allocation exhausted"}]}

    monkeypatch.setattr(backends.requests, "post", lambda *args, **kwargs: Response())
    with pytest.raises(backends.QuotaExceeded) as caught:
        backends.CloudflareBackend(
            account_id="account", api_token="token", retries=0
        ).generate("draw", reference_image)
    assert "Cloudflare Workers AI" in str(caught.value)
