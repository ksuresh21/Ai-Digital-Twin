"""Live image backends. API keys are read only from the environment."""

import base64
import io
import os
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import requests
from PIL import Image


class BackendError(RuntimeError):
    pass


class BackendRefusal(BackendError):
    pass


class QuotaExceeded(BackendError):
    """A provider quota/billing limit that should stop the current batch."""


@dataclass
class GeneratedImage:
    image: Image.Image
    backend: str
    usage: dict = field(default_factory=dict)


class ImageBackend(Protocol):
    name: str

    def generate(self, prompt: str, reference: Path) -> GeneratedImage: ...


class OpenAIBackend:
    name = "openai"

    def __init__(self, api_key: str | None = None, retries: int = 3, timeout: int = 180):
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")
        self.retries = retries
        self.timeout = timeout
        if not self.api_key:
            raise BackendError("OPENAI_API_KEY was not found in the environment")

    def generate(self, prompt: str, reference: Path) -> GeneratedImage:
        last_error = None
        for attempt in range(self.retries + 1):
            try:
                with reference.open("rb") as image_file:
                    response = requests.post(
                        "https://api.openai.com/v1/images/edits",
                        headers={"Authorization": f"Bearer {self.api_key}"},
                        data={
                            "model": "gpt-image-1",
                            "prompt": prompt,
                            "size": "1536x1024",
                            "quality": "medium",
                            "background": "transparent",
                            "output_format": "png",
                            "input_fidelity": "high",
                        },
                        files={"image": (reference.name, image_file, "image/png")},
                        timeout=self.timeout,
                    )
                if response.status_code == 429 or 500 <= response.status_code < 600:
                    last_error = BackendError(
                        f"OpenAI returned HTTP {response.status_code}: {_error_text(response)}"
                    )
                    if attempt < self.retries:
                        time.sleep(min(2 ** attempt, 8))
                        continue
                    raise last_error
                if response.status_code >= 400:
                    message = _error_text(response)
                    if response.status_code in (400, 403) and any(
                        word in message.lower() for word in ("safety", "policy", "refus")
                    ):
                        raise BackendRefusal(f"OpenAI refused the image request: {message}")
                    raise BackendError(f"OpenAI returned HTTP {response.status_code}: {message}")
                payload = response.json()
                encoded = payload.get("data", [{}])[0].get("b64_json")
                if not encoded:
                    raise BackendError("OpenAI returned no image data")
                image = Image.open(io.BytesIO(base64.b64decode(encoded))).convert("RGBA")
                return GeneratedImage(image, self.name, payload.get("usage", {}))
            except (requests.Timeout, requests.ConnectionError) as error:
                last_error = BackendError(f"OpenAI connection failed: {error}")
                if attempt < self.retries:
                    time.sleep(min(2 ** attempt, 8))
                    continue
                raise last_error
        raise last_error or BackendError("OpenAI generation failed")


class GeminiBackend:
    name = "gemini"

    def __init__(self, api_key: str | None = None):
        self.api_key = api_key or os.environ.get("GEMINI_API_KEY")
        if not self.api_key:
            raise BackendError("GEMINI_API_KEY was not found in the environment")

    def generate(self, prompt: str, reference: Path) -> GeneratedImage:
        try:
            client = _create_gemini_client(self.api_key)
            interaction = client.interactions.create(
                model="models/gemini-3.1-flash-lite-image",
                input=[
                    {"type": "text", "text": prompt},
                    {
                        "type": "image",
                        "data": base64.b64encode(reference.read_bytes()).decode("ascii"),
                        "mime_type": "image/png",
                    },
                ],
                generation_config={
                    "temperature": 1,
                    "max_output_tokens": 65536,
                    "top_p": 0.95,
                    "thinking_level": "minimal",
                },
                response_modalities=["image", "text"],
            )
            return _generated_image_from_interaction(interaction)
        except (BackendError, BackendRefusal):
            raise
        except Exception as error:
            if _is_quota_error(error):
                raise QuotaExceeded(_quota_message(error)) from error
            raise BackendError(f"Gemini generation failed: {error}") from error


class CloudflareBackend:
    name = "cloudflare"
    model = "@cf/black-forest-labs/flux-2-klein-4b"

    def __init__(self, account_id: str | None = None, api_token: str | None = None,
                 retries: int = 2, timeout: int = 180):
        self.account_id = account_id or os.environ.get("CLOUDFLARE_ACCOUNT_ID")
        self.api_token = api_token or os.environ.get("CLOUDFLARE_API_TOKEN")
        self.retries = retries
        self.timeout = timeout
        if not self.account_id or not self.api_token:
            raise BackendError(
                "CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are both required"
            )

    def generate(self, prompt: str, reference: Path) -> GeneratedImage:
        url = (
            f"https://api.cloudflare.com/client/v4/accounts/{self.account_id}/ai/run/"
            f"{self.model}"
        )
        reference_png = _cloudflare_reference_png(reference)
        last_error = None
        for attempt in range(self.retries + 1):
            try:
                response = requests.post(
                    url,
                    headers={"Authorization": f"Bearer {self.api_token}"},
                    data={
                        "prompt": (
                            "Use input image 0 as the exact character and visual-style reference. "
                            + prompt
                        ),
                        "width": "1536",
                        "height": "1024",
                        "guidance": "4",
                    },
                    files={"input_image_0": ("reference.png", reference_png, "image/png")},
                    timeout=self.timeout,
                )
                if response.status_code == 429:
                    raise QuotaExceeded(
                        "Cloudflare Workers AI quota is unavailable (HTTP 429). "
                        "Wait for the daily free allocation to reset or check Workers AI usage."
                    )
                if 500 <= response.status_code < 600:
                    last_error = BackendError(
                        f"Cloudflare returned HTTP {response.status_code}: {_error_text(response)}"
                    )
                    if attempt < self.retries:
                        time.sleep(min(2 ** attempt, 8))
                        continue
                    raise last_error
                if response.status_code >= 400:
                    message = _error_text(response)
                    if response.status_code == 403 and any(
                        word in message.lower() for word in ("quota", "neuron", "plan", "billing")
                    ):
                        raise QuotaExceeded(
                            f"Cloudflare Workers AI free access is unavailable (HTTP 403): {message}"
                        )
                    raise BackendError(
                        f"Cloudflare returned HTTP {response.status_code}: {message}"
                    )
                payload = response.json()
                result = payload.get("result", payload)
                encoded = result.get("image") if isinstance(result, dict) else None
                if not encoded:
                    raise BackendError("Cloudflare returned no image data")
                if encoded.startswith("data:"):
                    encoded = encoded.split(",", 1)[-1]
                image = Image.open(io.BytesIO(base64.b64decode(encoded))).convert("RGBA")
                return GeneratedImage(
                    image,
                    self.name,
                    {"model": self.model, "usage": result.get("usage", {})},
                )
            except QuotaExceeded:
                raise
            except (requests.Timeout, requests.ConnectionError) as error:
                last_error = BackendError(f"Cloudflare connection failed: {error}")
                if attempt < self.retries:
                    time.sleep(min(2 ** attempt, 8))
                    continue
                raise last_error
        raise last_error or BackendError("Cloudflare generation failed")


def _cloudflare_reference_png(reference: Path) -> bytes:
    with Image.open(reference) as source:
        image = source.convert("RGBA")
        image.thumbnail((511, 511), Image.Resampling.LANCZOS)
        output = io.BytesIO()
        image.save(output, format="PNG")
        return output.getvalue()


def _create_gemini_client(api_key: str):
    try:
        from google import genai
    except ImportError as error:
        raise BackendError("google-genai>=2.21,<3 is required for the Gemini backend") from error
    client = genai.Client(api_key=api_key)
    if not hasattr(client, "interactions"):
        version = getattr(genai, "__version__", "unknown")
        raise BackendError(
            f"google-genai {version} does not support the Interactions API; "
            "install google-genai>=2.21,<3"
        )
    return client


def _generated_image_from_interaction(interaction) -> GeneratedImage:
    text_parts = []
    for step in getattr(interaction, "steps", []) or []:
        if getattr(step, "type", None) != "model_output" or not getattr(step, "content", None):
            continue
        for part in step.content:
            part_type = getattr(part, "type", None)
            if part_type == "text" and getattr(part, "text", None):
                text_parts.append(part.text)
            elif part_type == "image" and getattr(part, "data", None):
                data = part.data
                if isinstance(data, str):
                    data = base64.b64decode(data)
                image = Image.open(io.BytesIO(data)).convert("RGBA")
                return GeneratedImage(image, "gemini", _interaction_usage(interaction))
    if text_parts:
        raise BackendRefusal(
            f"Gemini returned text instead of an image: {' '.join(text_parts)[:240]}"
        )
    raise BackendError("Gemini returned no image data")


def _interaction_usage(interaction) -> dict:
    usage = getattr(interaction, "usage", None)
    if usage is None:
        return {}
    if isinstance(usage, dict):
        return usage
    if hasattr(usage, "model_dump"):
        return usage.model_dump(exclude_none=True)
    return {key: value for key, value in vars(usage).items() if not key.startswith("_")}


def _is_quota_error(error: Exception) -> bool:
    message = str(error).lower()
    status_code = getattr(error, "status_code", None) or getattr(error, "code", None)
    return status_code == 429 or "error code: 429" in message or "quota exceeded" in message


def _quota_message(error: Exception) -> str:
    import re

    message = str(error)
    retry = ""
    match = re.search(r"retry in ([0-9.]+)s", message, flags=re.IGNORECASE)
    if match:
        retry = f" The provider suggested retrying after about {round(float(match.group(1)))} seconds."
    if "limit: 0" in message.lower():
        retry = " This project currently has a zero request quota, so waiting alone may not help."
    return (
        "Gemini quota is unavailable for this API project (HTTP 429). "
        "Check the Gemini plan, billing, and rate-limit dashboard before retrying."
        + retry
    )


def _error_text(response: requests.Response) -> str:
    try:
        payload = response.json()
        return str(payload.get("error", {}).get("message") or payload)[:500]
    except Exception:
        return response.text[:500]


def available_backend_names() -> list[str]:
    names = []
    if os.environ.get("OPENAI_API_KEY"):
        names.append("openai")
    if os.environ.get("GEMINI_API_KEY"):
        names.append("gemini")
    if os.environ.get("CLOUDFLARE_ACCOUNT_ID") and os.environ.get("CLOUDFLARE_API_TOKEN"):
        names.append("cloudflare")
    return names
