"""Disk-backed browser sessions and background generation orchestration."""

import hashlib
import json
import os
import threading
import time
import uuid
from pathlib import Path

from PIL import Image

from .backends import CloudflareBackend, GeminiBackend, ImageBackend, OpenAIBackend, QuotaExceeded
from .clips import CLIPS, CLIP_BY_NAME
from .image_ops import normalize, run_qa, save_frames, slice_sheet
from .packaging import build_zip
from .prompts import assemble_prompts


class SessionStore:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.sessions = self.root / "sessions"
        self.cache = self.root / ".cache"
        self.current_file = self.root / "current_session"
        self.sessions.mkdir(parents=True, exist_ok=True)
        self.cache.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def create(self, reference_source, config: dict) -> dict:
        session_id = uuid.uuid4().hex
        path = self.sessions / session_id
        (path / "raw").mkdir(parents=True)
        (path / "frames").mkdir()
        Image.open(reference_source).convert("RGBA").save(path / "reference.png")
        selected = set(config["clips"])
        state = {
            "id": session_id,
            "createdAt": int(time.time()),
            "config": config,
            "reference": f"/media/{session_id}/reference.png",
            "generationCount": 0,
            "running": False,
            "runError": None,
            "build": None,
            "clips": {
                spec.name: {
                    "name": spec.name,
                    "status": "queued" if spec.name in selected else "skipped",
                    "included": spec.name in selected,
                    "backend": None,
                    "frames": [],
                    "qa": [],
                    "error": None,
                    "sheet": None,
                    "attempts": [],
                    "regenerations": 0,
                }
                for spec in CLIPS
            },
        }
        self.save(state)
        self.current_file.write_text(session_id, encoding="utf-8")
        return state

    def create_manual(self, config: dict) -> dict:
        """Create a prompt/import session without calling an image API."""
        session_id = uuid.uuid4().hex
        path = self.sessions / session_id
        for folder in ("sources", "raw", "slices", "frames"):
            (path / folder).mkdir(parents=True, exist_ok=True)
        selected = set(config["clips"])
        state = {
            "id": session_id,
            "mode": "manual",
            "stage": "prompts",
            "createdAt": int(time.time()),
            "config": config,
            "reference": None,
            "referenceSource": None,
            "referenceCleanup": None,
            "generationCount": 0,
            "running": False,
            "runError": None,
            "build": None,
            "lastImport": None,
            "clips": {
                spec.name: {
                    "name": spec.name,
                    "status": "awaiting" if spec.name in selected else "skipped",
                    "included": spec.name in selected,
                    "backend": "manual" if spec.name in selected else None,
                    "frames": [],
                    "qa": [],
                    "error": None,
                    "sheet": None,
                    "sourceSheet": None,
                    "cleanup": None,
                    "split": None,
                    "attempts": [],
                    "regenerations": 0,
                }
                for spec in CLIPS
            },
        }
        self.save(state)
        self.current_file.write_text(session_id, encoding="utf-8")
        return state

    def path(self, session_id: str) -> Path:
        if not session_id.isalnum():
            raise ValueError("Invalid session id")
        path = (self.sessions / session_id).resolve()
        if path.parent != self.sessions or not path.is_dir():
            raise FileNotFoundError("Session not found")
        return path

    def load(self, session_id: str) -> dict:
        with self._lock:
            return json.loads((self.path(session_id) / "state.json").read_text(encoding="utf-8"))

    def current(self) -> dict | None:
        if not self.current_file.exists():
            return None
        try:
            return self.load(self.current_file.read_text(encoding="utf-8").strip())
        except (OSError, ValueError, FileNotFoundError, json.JSONDecodeError):
            return None

    def save(self, state: dict) -> None:
        with self._lock:
            path = self.sessions / state["id"] / "state.json"
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, indent=2), encoding="utf-8")
            temporary.replace(path)

    def mutate(self, session_id: str, function):
        with self._lock:
            state = self.load(session_id)
            function(state)
            self.save(state)
            return state

    def clear_current(self) -> None:
        with self._lock:
            if self.current_file.exists():
                self.current_file.unlink()

    def begin_application_run(self) -> None:
        """Recover the old job for safety, then start this process on setup."""
        self.recover_interrupted_current()
        self.clear_current()

    def recover_interrupted_current(self) -> dict | None:
        """Turn stale in-flight work into an actionable state after restart."""
        state = self.current()
        if state is None:
            return None
        interrupted = state.get("running", False) or any(
            item["status"] == "generating" for item in state["clips"].values()
        )
        if not interrupted:
            return state
        changed = False
        for item in state["clips"].values():
            if item["status"] in {"queued", "generating"}:
                item.update(
                    status="failed",
                    error=("Generation was interrupted when the local server stopped. "
                           "Regenerate this clip or start a new character."),
                )
                changed = True
        state["running"] = False
        if changed:
            state["runError"] = (
                "The previous run was interrupted when the application stopped. "
                "Completed clips were kept."
            )
        self.save(state)
        return state


class GenerationManager:
    def __init__(self, store: SessionStore, backends: dict[str, ImageBackend] | None = None):
        self.store = store
        self.backends = backends if backends is not None else self._environment_backends()
        self._threads: dict[str, threading.Thread] = {}
        self._generation_lock = threading.RLock()

    @staticmethod
    def _environment_backends() -> dict[str, ImageBackend]:
        result = {}
        if os.environ.get("OPENAI_API_KEY"):
            result["openai"] = OpenAIBackend()
        if os.environ.get("GEMINI_API_KEY"):
            result["gemini"] = GeminiBackend()
        if os.environ.get("CLOUDFLARE_ACCOUNT_ID") and os.environ.get("CLOUDFLARE_API_TOKEN"):
            result["cloudflare"] = CloudflareBackend()
        return result

    def start_all(self, session_id: str) -> None:
        self._start(session_id, lambda: self._generate_all(session_id))

    def regenerate(self, session_id: str, clip: str) -> None:
        if clip not in CLIP_BY_NAME:
            raise ValueError("Unknown clip")
        self.store.mutate(session_id, lambda state: self._queue_regeneration(state, clip))
        self._start(f"{session_id}:{clip}", lambda: self._generate_one(session_id, clip, True))

    def _start(self, key: str, target) -> None:
        current = self._threads.get(key)
        if current and current.is_alive():
            raise RuntimeError("That generation is already running")
        thread = threading.Thread(target=target, daemon=True, name=f"generation-{key[:12]}")
        self._threads[key] = thread
        thread.start()

    @staticmethod
    def _queue_regeneration(state: dict, clip: str) -> None:
        item = state["clips"][clip]
        item.update({"status": "queued", "error": None})
        item["regenerations"] += 1
        state["build"] = None

    def _generate_all(self, session_id: str) -> None:
        self.store.mutate(session_id, lambda state: state.update(running=True, runError=None))
        try:
            state = self.store.load(session_id)
            requested = state["config"]["clips"]
            for index, clip in enumerate(requested):
                latest = self.store.load(session_id)["clips"][clip]
                if latest["status"] in {"ready", "generating"}:
                    continue
                outcome = self._generate_one(session_id, clip, False)
                if outcome == "quota":
                    remaining = requested[index + 1:]
                    failed = self.store.load(session_id)["clips"][clip]
                    self.store.mutate(session_id, lambda current: self._stop_for_quota(
                        current, remaining, failed.get("error")
                    ))
                    break
        finally:
            self.store.mutate(session_id, lambda state: state.update(running=False))

    @staticmethod
    def _stop_for_quota(state: dict, remaining: list[str], provider_error: str | None) -> None:
        message = provider_error or (
            "Generation stopped because the selected provider quota is unavailable."
        )
        state["runError"] = message
        for clip in remaining:
            item = state["clips"][clip]
            if item["status"] == "queued":
                item.update(status="failed", error=message, errorKind="quota")

    def _backend_order(self, preferred: str) -> list[str]:
        if preferred in {"gemini", "cloudflare"}:
            return [preferred] if preferred in self.backends else []
        order = []
        if "openai" in self.backends:
            order.append("openai")
        if "cloudflare" in self.backends:
            order.append("cloudflare")
        if "gemini" in self.backends:
            order.append("gemini")
        return order

    def _generate_one(self, session_id: str, clip: str, regeneration: bool) -> str:
        self.store.mutate(session_id, lambda state: state["clips"][clip].update(
            status="generating", error=None
        ))
        state = self.store.load(session_id)
        path = self.store.path(session_id)
        reference_path = path / "reference.png"
        prompts = assemble_prompts(state["config"].get("sheet", {}))
        base_prompt = prompts[clip]
        regen_number = state["clips"][clip]["regenerations"]
        if regeneration or regen_number:
            base_prompt += (
                f"\n\nREGENERATION ATTEMPT {regen_number}: correct composition, frame count, "
                "transparency, scale drift, and registration while preserving the character."
            )
        order = self._backend_order(state["config"].get("backend", "openai"))
        if not order:
            self._fail(session_id, clip, "No usable image backend is configured")
            return "failed"

        accepted = None
        last_successful_candidate = None
        quota_error = None
        errors = []
        for backend_name in order:
            # The brief requires two OpenAI QA attempts before a Gemini fallback.
            qa_attempts = 2 if backend_name == "openai" and "gemini" in order else 1
            for qa_index in range(qa_attempts):
                prompt = base_prompt
                if qa_index:
                    prompt += "\n\nSECOND QA ATTEMPT: fix every measurable defect from the previous sheet."
                try:
                    generated, cache_hit = self._generate_cached(
                        self.backends[backend_name], prompt, reference_path
                    )
                    raw_frames = slice_sheet(generated.image)
                    preview = normalize({clip: raw_frames}, state["config"]["height"])
                    qa = run_qa(clip, raw_frames, preview.frames.get(clip, []),
                                Image.open(reference_path).convert("RGBA"))
                    passed = all(check["passed"] for check in qa)
                    attempt_record = {
                        "backend": backend_name,
                        "cacheHit": cache_hit,
                        "qaPassed": passed,
                        "usage": generated.usage,
                        "cost": {"currency": "USD", "amount": None,
                                 "note": "provider did not return a billable amount"},
                    }
                    self.store.mutate(session_id, lambda current: self._record_attempt(
                        current, clip, attempt_record, not cache_hit
                    ))
                    accepted = (generated.image, raw_frames, qa, backend_name)
                    last_successful_candidate = accepted
                    if passed or backend_name == "gemini" or qa_index + 1 == qa_attempts:
                        break
                except QuotaExceeded as error:
                    quota_error = error
                    errors.append(f"{backend_name}: {error}")
                    accepted = None
                    break
                except Exception as error:
                    errors.append(f"{backend_name}: {error}")
                    accepted = None
                    break
            if quota_error is not None:
                break
            if accepted and (all(check["passed"] for check in accepted[2]) or backend_name == "gemini"):
                break
            if accepted and backend_name == "openai" and "gemini" in order:
                accepted = None

        # If a QA-triggered fallback backend fails outright, retain the latest
        # successfully drawn OpenAI sheet with its amber QA flags. A measurable
        # warning must not throw away art the user is allowed to accept.
        accepted = accepted or last_successful_candidate
        if accepted is None:
            self._fail(
                session_id, clip, "; ".join(errors) or "Image generation failed",
                "quota" if quota_error else "provider",
            )
            return "quota" if quota_error else "failed"
        image, _, qa, backend_name = accepted
        raw_path = path / "raw" / f"{clip}.png"
        image.save(raw_path)
        self.store.mutate(session_id, lambda current: current["clips"][clip].update(
            status="ready", backend=backend_name, qa=qa, error=None,
            sheet=f"/media/{session_id}/raw/{clip}.png",
        ))
        self.refresh_previews(session_id)
        return "quota" if quota_error else "ready"

    @staticmethod
    def _record_attempt(state: dict, clip: str, record: dict, generation_used: bool) -> None:
        state["clips"][clip]["attempts"].append(record)
        if generation_used:
            state["generationCount"] += 1

    def _generate_cached(self, backend: ImageBackend, prompt: str, reference: Path):
        digest = hashlib.sha256()
        digest.update(backend.name.encode("utf-8"))
        digest.update(prompt.encode("utf-8"))
        digest.update(reference.read_bytes())
        cache_path = self.store.cache / f"{digest.hexdigest()}.png"
        if cache_path.exists():
            from .backends import GeneratedImage
            return GeneratedImage(Image.open(cache_path).convert("RGBA"), backend.name,
                                  {"source": "cache"}), True
        generated = backend.generate(prompt, reference)
        generated.image.save(cache_path)
        return generated, False

    def _fail(self, session_id: str, clip: str, message: str, error_kind: str = "provider") -> None:
        self.store.mutate(session_id, lambda state: state["clips"][clip].update(
            status="failed", error=message, errorKind=error_kind,
            backend=None, frames=[], qa=[]
        ))

    def refresh_previews(self, session_id: str) -> None:
        with self._generation_lock:
            state = self.store.load(session_id)
            path = self.store.path(session_id)
            raw = {}
            for clip, item in state["clips"].items():
                raw_path = path / "raw" / f"{clip}.png"
                if item["status"] == "ready" and raw_path.exists():
                    raw[clip] = slice_sheet(Image.open(raw_path).convert("RGBA"))
            normalized = normalize(raw, state["config"]["height"])
            reference = Image.open(path / "reference.png").convert("RGBA")
            updates = {}
            for clip, frames in normalized.frames.items():
                frame_dir = path / "frames" / clip
                if frame_dir.exists():
                    for old in frame_dir.glob("*.png"):
                        old.unlink()
                names = save_frames(frames, frame_dir)
                checks = run_qa(clip, raw[clip], frames, reference)
                updates[clip] = {
                    "frames": [f"/media/{session_id}/frames/{clip}/{name}" for name in names],
                    "qa": checks,
                }
            # Merge preview-only fields into the newest state. Include toggles,
            # build results, or status changes made during image processing must
            # never be overwritten by a stale snapshot.
            def merge(current):
                for clip, values in updates.items():
                    current["clips"][clip].update(values)

            self.store.mutate(session_id, merge)

    def set_included(self, session_id: str, clip: str, included: bool) -> dict:
        if clip == "idle" and not included:
            raise ValueError("Idle is required and cannot be excluded")
        if clip not in CLIP_BY_NAME:
            raise ValueError("Unknown clip")
        return self.store.mutate(session_id, lambda state: state["clips"][clip].update(
            included=bool(included)
        ))

    def build(self, session_id: str) -> tuple[Path, dict]:
        state = self.store.load(session_id)
        path = self.store.path(session_id)
        frames = {}
        details = {}
        for clip, item in state["clips"].items():
            if item["status"] == "ready" and item["included"]:
                raw_path = path / "raw" / f"{clip}.png"
                if raw_path.exists():
                    frames[clip] = slice_sheet(Image.open(raw_path).convert("RGBA"))
            details[clip] = {
                "status": item["status"], "included": item["included"],
                "backend": item["backend"], "checks": item["qa"],
                "attempts": item["attempts"],
            }
        output = path / f"{state['config']['name']}.zip"
        zip_path, summary, _ = build_zip(
            state["config"]["name"], path / "reference.png", frames, output,
            state["config"]["height"], details, force=True,
        )
        build_result = {
            "zip": f"/media/{session_id}/{zip_path.name}",
            "report": f"/media/{session_id}/report.json",
            "summary": summary,
        }
        self.store.mutate(session_id, lambda current: current.update(build=build_result))
        return zip_path, build_result
