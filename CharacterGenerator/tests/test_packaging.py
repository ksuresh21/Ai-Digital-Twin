import json
import subprocess
import sys
import zipfile
from pathlib import Path

from character_generator.packaging import build_zip
from conftest import rectangle_sheet


def test_idle_only_pack_is_valid_and_reports_fallbacks(reference_image, tmp_path):
    output = tmp_path / "Nish.zip"
    _, summary, normalized = build_zip(
        "Nish", reference_image, {"idle": [rectangle_sheet(2)]}, output
    )
    assert output.exists()
    assert summary["included"] == ["idle"]
    assert len(summary["excluded"]) == 13
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        assert "Nish/pack.json" in names
        assert "Nish/reference.png" in names
        assert "Nish/Idle/idle_01.png" in names
        manifest = json.loads(archive.read("Nish/pack.json"))
        assert manifest == normalized.manifest
        assert manifest["baseline"] == manifest["canvasHeight"] - 16
    report = json.loads((tmp_path / "report.json").read_text())
    assert report["summary"]["included"] == ["idle"]


def test_from_sheets_builds_without_network(reference_image, tmp_path):
    sheets = tmp_path / "sheets"
    sheets.mkdir()
    rectangle_sheet(2).save(sheets / "idle_sheet.png")
    output = tmp_path / "Offline.zip"
    result = subprocess.run(
        [sys.executable, "generate_character.py", str(reference_image), "--name", "Offline",
         "--from-sheets", str(sheets), "--out", str(output)],
        cwd=Path(__file__).resolve().parents[1], text=True, capture_output=True,
        env={"PATH": __import__("os").environ.get("PATH", "")},
    )
    assert result.returncode == 0, result.stderr
    assert output.exists()
    with zipfile.ZipFile(output) as archive:
        assert "Offline/Idle/idle_02.png" in archive.namelist()
    report = json.loads((tmp_path / "report.json").read_text())
    assert report["clips"]["idle"]["cost"]["amount"] == 0
    assert report["clips"]["idle"]["checks"]


def test_existing_zip_requires_force(reference_image, tmp_path):
    output = tmp_path / "Keep.zip"
    output.write_bytes(b"existing")
    try:
        build_zip("Keep", reference_image, {"idle": [rectangle_sheet(2)]}, output)
    except FileExistsError:
        pass
    else:
        raise AssertionError("existing output was overwritten without force")
    assert output.read_bytes() == b"existing"
