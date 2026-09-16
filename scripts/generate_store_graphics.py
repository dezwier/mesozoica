#!/usr/bin/env python3
"""Generate store graphics and opaque sandstone app icons."""

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
IOS_ICON_DIR = ROOT / "flutter" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ANDROID_RES = ROOT / "flutter" / "android" / "app" / "src" / "main" / "res"

BROWN = (62, 39, 35)
SAND = (196, 164, 132)
CREAM = (245, 235, 224)
DARK = (28, 27, 31)
# Theme light surfaceContainerHighest — museum sandstone slab.
SANDSTONE = (232, 224, 219)

ANDROID_LAUNCHERS = (
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
)


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


def _icon_on_sandstone(size: int) -> Image.Image:
    canvas = Image.new("RGB", (size, size), SANDSTONE)
    glow = Image.new("RGB", (size, size), SANDSTONE)
    inset = round(size * 0.08)
    ImageDraw.Draw(glow).ellipse(
        (inset, round(size * 0.11), size - inset, size - round(size * 0.05)),
        fill=(214, 196, 178),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(max(4, round(size * 0.055))))
    canvas = Image.blend(canvas, glow, 0.55)

    logo = _knockout_black(Image.open(LOGO_PATH))
    max_side = round(size * 0.78)
    scale = min(max_side / logo.width, max_side / logo.height)
    logo = logo.resize(
        (max(1, round(logo.width * scale)), max(1, round(logo.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas.paste(
        logo,
        ((size - logo.width) // 2, (size - logo.height) // 2 + round(size * 0.016)),
        logo,
    )
    return canvas


def write_icon() -> None:
    canvas = _icon_on_sandstone(512)
    out = OUT_DIR / "icon-512.png"
    canvas.save(out, "PNG", optimize=True)
    print(f"wrote {out} {canvas.size}")


def write_platform_icons() -> None:
    if IOS_ICON_DIR.exists():
        for path in sorted(IOS_ICON_DIR.glob("*.png")):
            size = Image.open(path).size[0]
            _icon_on_sandstone(size).save(path, "PNG", optimize=True)
            print(f"wrote {path} {size}x{size}")
    for folder, size in ANDROID_LAUNCHERS:
        dest_dir = ANDROID_RES / folder
        if not dest_dir.exists():
            continue
        dest = dest_dir / "ic_launcher.png"
        _icon_on_sandstone(size).save(dest, "PNG", optimize=True)
        print(f"wrote {dest} {size}x{size}")


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
    write_platform_icons()
    write_feature_graphic()


if __name__ == "__main__":
    main()
