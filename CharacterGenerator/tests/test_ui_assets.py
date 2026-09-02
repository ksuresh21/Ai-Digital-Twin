from pathlib import Path


def test_manual_import_uses_static_missing_and_failed_states():
    root = Path(__file__).resolve().parents[1]
    script = (root / "static" / "app.js").read_text()
    stylesheet = (root / "static" / "style.css").read_text()

    assert 'class="waiting stopped"' in script
    assert 'class="stopped-icon"' in script
    assert ".waiting .stopped-icon" in stylesheet
    assert "Sheet missing from folder" in script
    assert "Could not process sheet" in script
    assert "setInterval(refresh" not in script
    assert "generation stopped" not in script.lower()
