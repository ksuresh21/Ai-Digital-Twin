from pathlib import Path

from character_generator.backends import GeneratedImage, QuotaExceeded
from character_generator.session import GenerationManager, SessionStore
from conftest import rectangle_sheet


class FakeBackend:
    def __init__(self, name, image):
        self.name = name
        self.image = image
        self.calls = 0

    def generate(self, prompt, reference):
        self.calls += 1
        return GeneratedImage(self.image.copy(), self.name, {"fake": True})


class FailingBackend:
    name = "gemini"

    def generate(self, prompt, reference):
        raise RuntimeError("temporary provider failure")


class QuotaBackend:
    name = "gemini"

    def __init__(self):
        self.calls = 0

    def generate(self, prompt, reference):
        self.calls += 1
        raise QuotaExceeded("Gemini quota is unavailable (HTTP 429)")


def config(clips):
    return {"name": "Nish", "height": 470, "clips": clips,
            "backend": "openai", "sheet": {}}


def test_state_survives_new_store_instance(reference_image, tmp_path):
    root = tmp_path / "work"
    first = SessionStore(root)
    state = first.create(reference_image, config(["idle"]))
    second = SessionStore(root)
    assert second.current()["id"] == state["id"]
    assert second.load(state["id"])["clips"]["idle"]["status"] == "queued"


def test_two_openai_qa_failures_trigger_gemini(reference_image, tmp_path):
    # Fully opaque and unsliceable, so every OpenAI QA pass fails.
    from PIL import Image
    bad = Image.new("RGBA", (300, 300), (220, 220, 220, 255))
    good = rectangle_sheet(2)
    openai = FakeBackend("openai", bad)
    gemini = FakeBackend("gemini", good)
    store = SessionStore(tmp_path / "work")
    state = store.create(reference_image, config(["idle"]))
    manager = GenerationManager(store, {"openai": openai, "gemini": gemini})
    manager._generate_one(state["id"], "idle", False)
    final = store.load(state["id"])
    assert openai.calls == 2
    assert gemini.calls == 1
    assert final["clips"]["idle"]["backend"] == "gemini"
    assert final["clips"]["idle"]["status"] == "ready"


def test_regenerating_one_clip_does_not_touch_another(reference_image, tmp_path):
    backend = FakeBackend("openai", rectangle_sheet(4))
    store = SessionStore(tmp_path / "work")
    state = store.create(reference_image, config(["idle", "walk"]))
    manager = GenerationManager(store, {"openai": backend})
    manager._generate_all(state["id"])
    session_path = store.path(state["id"])
    walk_before = (session_path / "raw" / "walk.png").read_bytes()
    walk_attempts = len(store.load(state["id"])["clips"]["walk"]["attempts"])
    store.mutate(state["id"], lambda current: manager._queue_regeneration(current, "idle"))
    manager._generate_one(state["id"], "idle", True)
    final = store.load(state["id"])
    assert (session_path / "raw" / "walk.png").read_bytes() == walk_before
    assert len(final["clips"]["walk"]["attempts"]) == walk_attempts


def test_failed_fallback_keeps_flagged_openai_art(reference_image, tmp_path):
    from PIL import Image
    bad_but_reviewable = Image.new("RGBA", (300, 300), (220, 220, 220, 255))
    openai = FakeBackend("openai", bad_but_reviewable)
    store = SessionStore(tmp_path / "work")
    state = store.create(reference_image, config(["idle"]))
    manager = GenerationManager(store, {"openai": openai, "gemini": FailingBackend()})
    manager._generate_one(state["id"], "idle", False)
    final = store.load(state["id"])["clips"]["idle"]
    assert final["status"] == "ready"
    assert final["backend"] == "openai"
    assert any(not check["passed"] for check in final["qa"])


def test_quota_failure_stops_remaining_batch(reference_image, tmp_path):
    backend = QuotaBackend()
    store = SessionStore(tmp_path / "work")
    state = store.create(reference_image, {
        "name": "Nish", "height": 470, "clips": ["idle", "walk", "wave"],
        "backend": "gemini", "sheet": {},
    })
    manager = GenerationManager(store, {"gemini": backend})
    manager._generate_all(state["id"])
    final = store.load(state["id"])
    assert backend.calls == 1
    assert final["running"] is False
    assert final["runError"]
    assert [final["clips"][name]["status"] for name in ("idle", "walk", "wave")] == [
        "failed", "failed", "failed"
    ]
    assert all(final["clips"][name]["errorKind"] == "quota"
               for name in ("idle", "walk", "wave"))


def test_restart_recovers_interrupted_session_and_can_clear_pointer(reference_image, tmp_path):
    root = tmp_path / "work"
    store = SessionStore(root)
    state = store.create(reference_image, config(["idle", "walk"]))
    state["running"] = True
    state["clips"]["idle"]["status"] = "generating"
    store.save(state)

    restarted = SessionStore(root)
    recovered = restarted.recover_interrupted_current()
    assert recovered["running"] is False
    assert recovered["runError"]
    assert recovered["clips"]["idle"]["status"] == "failed"
    assert recovered["clips"]["walk"]["status"] == "failed"

    restarted.clear_current()
    assert restarted.current() is None


def test_new_application_run_starts_on_setup_but_preserves_old_session(reference_image, tmp_path):
    root = tmp_path / "work"
    store = SessionStore(root)
    state = store.create(reference_image, config(["idle"]))
    state["running"] = True
    state["clips"]["idle"]["status"] = "generating"
    store.save(state)

    restarted = SessionStore(root)
    restarted.begin_application_run()

    assert restarted.current() is None
    preserved = restarted.load(state["id"])
    assert preserved["running"] is False
    assert preserved["clips"]["idle"]["status"] == "failed"


def test_cloudflare_precedes_gemini_for_legacy_openai_fallback(tmp_path):
    store = SessionStore(tmp_path / "work")
    cloudflare = FakeBackend("cloudflare", rectangle_sheet(4))
    gemini = FakeBackend("gemini", rectangle_sheet(4))
    manager = GenerationManager(store, {"gemini": gemini, "cloudflare": cloudflare})

    assert manager._backend_order("openai") == ["cloudflare", "gemini"]
