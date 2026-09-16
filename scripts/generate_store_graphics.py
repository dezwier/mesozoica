#!/usr/bin/env python3
"""Generate Play Store icon (512) and feature graphic (1024x500)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LOGO_PATH = ROOT / "flutter" / "assets" / "images" / "logo.png"
FONT_PATH = (
    ROOT
    / "flutter"
    / "assets"
    / "fonts"
    / "tt_ramillas"
    / "TT Ramillas Trial Bold.ttf"
)
OUT_DIR = ROOT / "marketing" / "play-store"

BROWN = (62, 39, 35)
SAND = (196, 164, 132)
CREAM = (245, 235, 224)
DARK = (28, 27, 31)


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


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_PATH), size=size)


def write_icon() -> None:
    canvas = Image.new("RGB", (512, 512), BROWN)
    glow = Image.new("RGB", (512, 512), BROWN)
    ImageDraw.Draw(glow).ellipse((40, 56, 472, 488), fill=(90, 58, 48))
    glow = glow.filter(ImageFilter.GaussianBlur(28))
    canvas = Image.blend(canvas, glow, 0.55)

    logo = _knockout_black(Image.open(LOGO_PATH))
    max_side = 400
    scale = min(max_side / logo.width, max_side / logo.height)
    logo = logo.resize(
        (round(logo.width * scale), round(logo.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas.paste(
        logo,
        ((512 - logo.width) // 2, (512 - logo.height) // 2 + 8),
        logo,
    )
    out = OUT_DIR / "icon-512.png"
    canvas.save(out, "PNG", optimize=True)
    print(f"wrote {out} {canvas.size}")


def write_feature_graphic() -> None:
    canvas = Image.new("RGB", (1024, 500), DARK)
    overlay = Image.new("RGB", (1024, 500), BROWN)
    ImageDraw.Draw(overlay).ellipse((-120, -180, 520, 620), fill=(90, 58, 48))
    overlay = overlay.filter(ImageFilter.GaussianBlur(48))
    canvas = Image.blend(canvas, overlay, 0.72)

    logo = _knockout_black(Image.open(LOGO_PATH))
    logo_h = 340
    scale = logo_h / logo.height
    logo = logo.resize(
        (round(logo.width * scale), logo_h),
        Image.Resampling.LANCZOS,
    )
    canvas.paste(logo, (48, (500 - logo.height) // 2), logo)

    draw = ImageDraw.Draw(canvas)
    title = _font(72)
    draw.text((430, 168), "MESOZOICA", font=title, fill=CREAM)
    subtitle = _font(28)
    draw.text(
        (430, 268),
        "Find fossils where you walk",
        font=subtitle,
        fill=SAND,
    )
    out = OUT_DIR / "feature-graphic.png"
    canvas.save(out, "PNG", optimize=True)
    print(f"wrote {out} {canvas.size}")


def main() -> None:
    if not LOGO_PATH.exists():
        raise SystemExit(f"Missing logo: {LOGO_PATH}")
    if not FONT_PATH.exists():
        raise SystemExit(f"Missing font: {FONT_PATH}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_icon()
    write_feature_graphic()


if __name__ == "__main__":
    main()
