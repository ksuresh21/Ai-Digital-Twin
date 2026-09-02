from PIL import Image, ImageDraw

from character_generator.image_ops import content_bbox, normalize, slice_sheet
from conftest import rectangle_sheet


def content_height(image):
    box = content_bbox(image)
    return box[3] - box[1]


def test_three_zoom_normalizes_to_one_canvas_and_height():
    raw = {
        "idle": [rectangle_sheet(1, 300, 900, 120)],
        "walk": [rectangle_sheet(1, 500, 700, 300)],
        "wave": [rectangle_sheet(1, 400, 1200, 160)],
    }
    result = normalize(raw, 470)
    heights = [content_height(result.frames[name][0]) for name in raw]
    assert all(abs(height - heights[0]) <= 2 for height in heights)
    assert all(abs(height - 470) <= 2 for height in heights)
    assert {frame.size for frames in result.frames.values() for frame in frames} == {
        (result.canvas_width, result.canvas_height)
    }


def test_contact_sheet_slices_four_frames_with_small_confetti():
    sheet = rectangle_sheet(4, 600, 300, 170)
    draw = ImageDraw.Draw(sheet)
    # Detached decoration is narrower than the relative sliver threshold.
    draw.rectangle((146, 50, 150, 54), fill=(255, 210, 40, 255))
    draw.rectangle((298, 80, 302, 84), fill=(255, 210, 40, 255))
    assert len(slice_sheet(sheet)) == 4


def test_narrow_decoration_run_never_becomes_an_extra_frame():
    sheet = rectangle_sheet(4, 600, 300, 170)
    ImageDraw.Draw(sheet).rectangle((145, 50, 156, 62), fill=(255, 210, 40, 255))
    pieces = slice_sheet(sheet)
    assert len(pieces) != 5


def test_feet_land_on_same_row_even_when_source_frames_drift():
    sheet = rectangle_sheet(4, 600, 300, 170, vertical_offsets=[0, 9, 3, 14])
    frames = slice_sheet(sheet)
    result = normalize({"walk": frames}, 470)
    bottoms = [content_bbox(frame)[3] - 1 for frame in result.frames["walk"]]
    assert max(bottoms) - min(bottoms) <= 1
    assert all(abs(bottom - (result.baseline - 1)) <= 1 for bottom in bottoms)


def test_peek_hugs_left_canvas_edge():
    image = Image.new("RGBA", (160, 220), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((50, 30, 140, 210), fill=(40, 120, 90, 255))
    result = normalize({"peek": [image]}, 470)
    box = content_bbox(result.frames["peek"][0])
    assert box[0] == 0
    assert box[2] < result.canvas_width // 2


def test_nearest_neighbor_keeps_palette_crisp():
    image = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rectangle((5, 2, 14, 18), fill=(10, 20, 30, 255))
    result = normalize({"idle": [image]}, 470)
    colors = set(result.frames["idle"][0].getdata())
    assert colors <= {(0, 0, 0, 0), (10, 20, 30, 255)}
