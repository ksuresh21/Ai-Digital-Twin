#!/usr/bin/env python3
"""Local-only browser interface for the AiTwin Character Generator."""

import threading
import webbrowser
from pathlib import Path

from flask import Flask, jsonify, render_template, request, send_from_directory

from character_generator.clips import CLIPS
from character_generator.environment import load_local_env
from character_generator.manual import ManualWorkflow
from character_generator.packaging import validate_pack_name
from character_generator.prompts import fields_for, placeholders, prompt_payload
from character_generator.session import SessionStore


ROOT = Path(__file__).resolve().parent
load_local_env(ROOT / ".env")
WORK_ROOT = ROOT / ".work"
app = Flask(__name__, static_folder="static", template_folder="templates")
app.config["MAX_CONTENT_LENGTH"] = 300 * 1024 * 1024
app.json.sort_keys = False
store = SessionStore(WORK_ROOT)
store.begin_application_run()
workflow = ManualWorkflow(store)


def error(message, status=400):
    return jsonify({"error": str(message)}), status


@app.get("/")
def index():
    return render_template(
        "index.html", clips=CLIPS, human_placeholders=placeholders("human"),
        pet_placeholders=placeholders("pet"),
    )


@app.get("/api/current")
def current():
    return jsonify(store.current())


@app.post("/api/new")
def new_character():
    store.clear_current()
    return jsonify({"ok": True})


@app.post("/api/setup")
def setup():
    try:
        config = request.get_json(silent=True) or {}
        config["name"] = validate_pack_name(config.get("name", ""))
        config["height"] = int(config.get("height", 470))
        if not 32 <= config["height"] <= 4096:
            return error("Target height must be between 32 and 4096")
        allowed = {clip.name for clip in CLIPS}
        config["clips"] = [clip for clip in config.get("clips", []) if clip in allowed]
        if not config["clips"]:
            return error("Select at least one clip")
        if "idle" not in config["clips"]:
            return error("Idle is required for an installable pack")
        subject_type = str(config.get("subjectType", "")).strip().lower()
        fields_for(subject_type)
        config["subjectType"] = subject_type
        raw_sheet = config.get("sheet") if isinstance(config.get("sheet"), dict) else {}
        allowed_fields = {key for key, _, _ in fields_for(subject_type)}
        config["sheet"] = {
            key: str(value).strip()[:300]
            for key, value in raw_sheet.items()
            if key in allowed_fields and str(value).strip()
        }
        state = store.create_manual(config)
        return jsonify(state), 201
    except Exception as exc:
        return error(exc)


@app.get("/api/sessions/<session_id>")
def session_state(session_id):
    try:
        return jsonify(store.load(session_id))
    except FileNotFoundError:
        return error("Session not found", 404)


@app.get("/api/sessions/<session_id>/prompts")
def prompts(session_id):
    try:
        state = store.load(session_id)
        config = state["config"]
        payload = prompt_payload(config["subjectType"], config.get("sheet", {}))
        payload["files"] = {
            "reference": "reference.png",
            "clips": {clip.name: f"{clip.name}.png" for clip in CLIPS},
        }
        return jsonify(payload)
    except Exception as exc:
        return error(exc)


@app.post("/api/sessions/<session_id>/import")
def import_folder(session_id):
    try:
        uploads = [item for item in request.files.getlist("files") if item.filename]
        return jsonify(workflow.import_folder(session_id, uploads))
    except FileNotFoundError:
        return error("Session not found", 404)
    except Exception as exc:
        return error(exc)


@app.post("/api/sessions/<session_id>/clips/<clip>/include")
def include(session_id, clip):
    try:
        state = workflow.set_included(session_id, clip, bool(request.json.get("included")))
        return jsonify(state)
    except Exception as exc:
        return error(exc)


@app.post("/api/sessions/<session_id>/build")
def build(session_id):
    try:
        _, result = workflow.build(session_id)
        return jsonify(result)
    except Exception as exc:
        return error(exc)


@app.get("/media/<session_id>/<path:filename>")
def media(session_id, filename):
    try:
        directory = store.path(session_id)
        return send_from_directory(directory, filename, as_attachment=filename.endswith((".zip", "report.json")))
    except FileNotFoundError:
        return error("File not found", 404)


def main():
    url = "http://127.0.0.1:5000"
    threading.Timer(0.8, lambda: webbrowser.open(url)).start()
    app.run(host="127.0.0.1", port=5000, debug=False, threaded=True)


if __name__ == "__main__":
    main()
