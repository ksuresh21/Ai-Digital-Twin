from pathlib import Path

import pytest
from PIL import Image, ImageDraw


@pytest.fixture
def reference_image(tmp_path: Path) -> Path:
    path = tmp_path / "reference.png"
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((22, 8, 42, 59), fill=(40, 120, 90, 255))
    image.save(path)
    return path


def rectangle_sheet(frame_count=4, width=500, height=300, figure_height=160,
                    color=(40, 120, 90, 255), vertical_offsets=None):
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    gap = width // frame_count
    vertical_offsets = vertical_offsets or [0] * frame_count
    for index in range(frame_count):
        centre = gap * index + gap // 2
        bottom = height - 20 - vertical_offsets[index]
        draw.rectangle((centre - 18, bottom - figure_height, centre + 18, bottom),
                       fill=color)
    return image
