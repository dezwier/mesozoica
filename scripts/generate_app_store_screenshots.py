#!/usr/bin/env python3
"""Compose Mesozoica App Store Connect screenshots (RGB, no alpha).

iPhone: 6.5" 1284 x 2778 and 6.9" 1320 x 2868.
iPad 13": 2064 x 2752.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "marketing" / "app-store" / "source"
LOGO_PATH = ROOT / "flutter" / "assets" / "images" / "logo.png"
HEADLINE_FONT = (
    ROOT
    / "flutter"
    / "assets"
    / "fonts"
    / "tt_ramillas"
    / "TT Ramillas Trial Bold.ttf"
)

IPHONE_CANVAS = (1320, 2868)
IPHONE_OUTPUTS = (
    ((1284, 2778), ROOT / "marketing" / "app-store" / "iphone-6.5"),
    ((1320, 2868), ROOT / "marketing" / "app-store" / "iphone-6.9"),
)
IPAD_CANVAS = (2064, 2752)
IPAD_OUTPUTS = (
    ((2064, 2752), ROOT / "marketing" / "app-store" / "ipad-13"),
)

DARK = (28, 27, 31)
BROWN = (62, 39, 35)
SAND = (196, 164, 132)
CREAM = (245, 235, 224)


@dataclass(frozen=True)
class Slide:
    source: str
    output: str
    headline: str
    accent: tuple[int, int, int]


SLIDES = (
    Slide(
        source="01-map-discovery.jpg",
        output="01-map-discovery.png",
        headline="Discover sites\nwhere you walk",
        accent=SAND,
    ),
    Slide(
        source="02-site-card.jpg",
        output="02-site-card.png",
        headline="Document real\ngeology",
        accent=(180, 120, 72),
    ),
    Slide(
        source="03-dinosaur-catalog.jpg",
        output="03-dinosaur-catalog.png",
        headline="A museum of\nliving deep time",
        accent=(212, 175, 55),
    ),
    Slide(
        source="04-fossils-tools.jpg",
        output="04-fossils-tools.png",
        headline="Excavate with\nreal tools",
        accent=(141, 110, 99),
    ),
    Slide(
        source="05-profile-skills.jpg",
        output="05-profile-skills.png",
        headline="Walk. Collect.\nCurate.",
        accent=(168, 140, 110),
    ),
)


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(HEADLINE_FONT), size=size)


def _knockout_black(image: Image.Image, threshold: int = 18) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if red <= threshold and green <= threshold and blue <= threshold:
                pixels[x, y] = (red, green, blue, 0)
    return rgba


def _radial_glow(
    size: tuple[int, int],
    color: tuple[int, int, int],
    center: tuple[int, int],
    radius: int,
    max_alpha: int,
) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    blob = Image.new("L", (radius * 2, radius * 2), 0)
    ImageDraw.Draw(blob).ellipse((0, 0, radius * 2 - 1, radius * 2 - 1), fill=max_alpha)
    blob = blob.filter(ImageFilter.GaussianBlur(radius * 0.42))
    colored = Image.new("RGBA", blob.size, (*color, 0))
    colored.putalpha(blob)
    layer.alpha_composite(colored, (center[0] - radius, center[1] - radius))
    return layer


def _round_corners(image: Image.Image, radius: int) -> Image.Image:
    rounded = image.convert("RGBA")
    mask = Image.new("L", rounded.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, rounded.width - 1, rounded.height - 1),
        radius=radius,
        fill=255,
    )
    rounded.putalpha(mask)
    return rounded


def _drop_shadow(
    size: tuple[int, int],
    box: tuple[int, int, int, int],
    radius: int,
) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow = Image.new("L", size, 0)
    draw = ImageDraw.Draw(shadow)
    left, top, right, bottom = box
    draw.rounded_rectangle(
        (left + 12, top + 28, right + 12, bottom + 36),
        radius=radius,
        fill=160,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    colored = Image.new("RGBA", size, (0, 0, 0, 0))
    colored.putalpha(shadow)
    layer.alpha_composite(colored)
    return layer


def _text_size(
    draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont
) -> tuple[int, int]:
    box = draw.multiline_textbbox((0, 0), text, font=font, align="center", spacing=8)
    return box[2] - box[0], box[3] - box[1]


def _fit_headline(
    draw: ImageDraw.ImageDraw,
    text: str,
    max_width: int,
    max_size: int,
    min_size: int,
) -> ImageFont.FreeTypeFont:
    for size in range(max_size, min_size - 1, -2):
        font = _font(size)
        width, _ = _text_size(draw, text, font)
        if width <= max_width:
            return font
    return _font(min_size)


def compose(slide: Slide, canvas_size: tuple[int, int]) -> Image.Image:
    width, height = canvas_size
    sx = width / 1320
    sy = height / 2868
    canvas = Image.new("RGBA", canvas_size, (*DARK, 255))
    canvas.alpha_composite(
        _radial_glow(canvas_size, BROWN, (round(660 * sx), round(180 * sy)), round(1100 * sx), 90)
    )
    canvas.alpha_composite(
        _radial_glow(
            canvas_size, slide.accent, (round(1180 * sx), round(520 * sy)), round(920 * sx), 64
        )
    )

    logo = _knockout_black(Image.open(LOGO_PATH))
    logo_h = max(72, round(96 * sx))
    logo = logo.resize(
        (round(logo.width * logo_h / logo.height), logo_h),
        Image.Resampling.LANCZOS,
    )
    logo_y = max(64, round(80 * sy))
    canvas.alpha_composite(logo, ((width - logo.width) // 2, logo_y))

    draw = ImageDraw.Draw(canvas)
    text_max_width = width - max(120, round(120 * sx))
    headline_font = _fit_headline(
        draw,
        slide.headline,
        text_max_width,
        max_size=max(72, round(92 * sx)),
        min_size=max(48, round(60 * sx)),
    )
    _, headline_h = _text_size(draw, slide.headline, headline_font)
    headline_y = logo_y + logo.height + max(20, round(28 * sy))
    draw.multiline_text(
        (width / 2, headline_y),
        slide.headline,
        font=headline_font,
        fill=CREAM,
        anchor="ma",
        align="center",
        spacing=max(4, round(6 * sx)),
    )

    source = Image.open(SOURCE_DIR / slide.source).convert("RGB")
    top_band = headline_y + headline_h + max(48, round(80 * sy))
    bottom_pad = max(56, round(72 * sy))
    side_pad = max(72, round(78 * sx))
    avail_w = width - side_pad * 2
    avail_h = height - top_band - bottom_pad
    scale = min(avail_w / source.width, avail_h / source.height)
    device_w = round(source.width * scale)
    device_h = round(source.height * scale)
    device = source.resize((device_w, device_h), Image.Resampling.LANCZOS)
    radius = max(48, round(device_w * 0.11))
    device_x = (width - device_w) // 2
    device_y = top_band + (avail_h - device_h) // 2
    box = (device_x, device_y, device_x + device_w, device_y + device_h)
    canvas.alpha_composite(_drop_shadow(canvas_size, box, radius))
    canvas.alpha_composite(_round_corners(device, radius), (device_x, device_y))
    return canvas.convert("RGB")


def _write_outputs(
    master: Image.Image,
    master_size: tuple[int, int],
    outputs: tuple[tuple[tuple[int, int], Path], ...],
    name: str,
) -> None:
    if master.size != master_size:
        raise SystemExit(f"{name} is {master.size}, expected {master_size}")
    for size, folder in outputs:
        image = (
            master
            if master.size == size
            else master.resize(size, Image.Resampling.LANCZOS)
        )
        folder.mkdir(parents=True, exist_ok=True)
        out = folder / name
        image.save(out, "PNG", optimize=True)
        print(f"wrote {out} {image.size} {image.mode}")


def main() -> None:
    if not HEADLINE_FONT.exists():
        raise SystemExit(f"Missing headline font: {HEADLINE_FONT}")
    missing = [slide.source for slide in SLIDES if not (SOURCE_DIR / slide.source).exists()]
    if missing:
        names = ", ".join(missing)
        raise SystemExit(
            f"Missing source captures in {SOURCE_DIR}: {names}. "
            "See marketing/app-store/source/README.md."
        )
    for slide in SLIDES:
        _write_outputs(compose(slide, IPHONE_CANVAS), IPHONE_CANVAS, IPHONE_OUTPUTS, slide.output)
        _write_outputs(compose(slide, IPAD_CANVAS), IPAD_CANVAS, IPAD_OUTPUTS, slide.output)


if __name__ == "__main__":
    main()
