import io
import zipfile

from PIL import Image, ImageDraw
from werkzeug.datastructures import FileStorage

from character_generator.manual import ManualWorkflow
from character_generator.prompts import assemble_prompts, assemble_reference_prompt
from character_generator.session import SessionStore


def upload(name, image):
    data = io.BytesIO()
    image.save(data, format="PNG")
    data.seek(0)
    return FileStorage(stream=data, filename=name, content_type="image/png")


def opaque_reference():
    image = Image.new("RGB", (128, 128), "white")
    ImageDraw.Draw(image).rectangle((45, 15, 83, 115), fill=(30, 110, 75))
    return image


def connected_four_frame_sheet():
    image = Image.new("RGB", (640, 360), "white")
    draw = ImageDraw.Draw(image)
    for index in range(4):
        centre = index * 160 + 80
        draw.rectangle((centre - 20, 90, centre + 20, 320), fill=(30, 110, 75))
    # Deliberately join all silhouettes. Transparent-run slicing sees one run,
    # so the declared equal-width 16:9 fallback must recover four frames.
    draw.line((60, 310, 580, 310), fill=(30, 110, 75), width=2)
    return image


def config():
    return {
        "name": "Manual Pet", "height": 470, "clips": ["idle"],
        "subjectType": "pet", "sheet": {"species": "cat"},
    }


def test_pet_prompts_are_complete_and_anatomically_adapted():
    reference = assemble_reference_prompt("pet", {"species": "cat", "markings": "white paws"})
    prompts = assemble_prompts({"species": "cat"}, "pet")

    assert "attached real pet photograph" in reference
    assert "SPECIES: cat" in reference
    assert "DISTINCTIVE MARKINGS: white paws" in reference
    drink = " ".join(prompts["drink"].split())  # prompts are hard-wrapped
    assert "simple pixel-art bowl on the ground" in drink
    # Anatomy now follows the reference rather than a blanket human-anatomy ban,
    # because this track also covers upright cartoon characters with hands.
    assert "never give it human hands" in drink
    assert "upright character with hands" in drink
    assert "exactly 2 frames ONLY" in prompts["focus"]
    assert "available landscape aspect ratio such as 16:9" in prompts["idle"]
    assert not any("[STYLE BLOCK]" in prompt for prompt in prompts.values())


def test_manual_folder_import_removes_background_uses_grid_fallback_and_builds(tmp_path):
    store = SessionStore(tmp_path / "work")
    state = store.create_manual(config())
    workflow = ManualWorkflow(store)

    result = workflow.import_folder(state["id"], [
        upload("generated/reference.png", opaque_reference()),
        upload("generated/idle.png", connected_four_frame_sheet()),
    ])

    idle = result["clips"]["idle"]
    assert result["stage"] == "review"
    assert result["referenceCleanup"]["changed"] is True
    assert idle["status"] == "ready"
    assert idle["cleanup"]["changed"] is True
    assert idle["split"]["method"] == "equal-width-fallback"
    assert len(idle["frames"]) == 4
    assert any(check["name"] == "sheet_split" and not check["passed"] for check in idle["qa"])

    output, built = workflow.build(state["id"])
    assert output.exists()
    assert built["summary"]["included"] == ["idle"]
    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        assert "Manual Pet/reference.png" in names
        assert "Manual Pet/Idle/idle_04.png" in names


def test_manual_import_requires_reference_image(tmp_path):
    store = SessionStore(tmp_path / "work")
    state = store.create_manual(config())
    workflow = ManualWorkflow(store)

    try:
        workflow.import_folder(state["id"], [upload("idle.png", connected_four_frame_sheet())])
    except ValueError as error:
        assert "reference.png" in str(error)
    else:
        raise AssertionError("folder without reference.png was accepted")
