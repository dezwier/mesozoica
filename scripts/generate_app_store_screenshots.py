#!/usr/bin/env python3
"""Compose Mesozoica App Store Connect screenshots (RGB, no alpha).

iPhone: 6.5" 1284 x 2778 and 6.9" 1320 x 2868.
iPad 12.9"/13": 2064 x 2752 (also accepted: 2048 x 2732).
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

# MesozoicaTheme light/dark surfaces used as a museum frame.
DARK = (28, 27, 31)
BROWN = (62, 39, 35)
PRIMARY = (141, 110, 99)
SECONDARY = (188, 170, 164)
ON_SURFACE_VARIANT = (93, 64, 55)
CREAM = (215, 204, 200)
ISLAND = (*ON_SURFACE_VARIANT, 255)


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
        accent=SECONDARY,
    ),
    Slide(
        source="02-dinosaur-triceratops.jpg",
        output="02-dinosaur-triceratops.png",
        headline="Dinosaurs as\nthey really were",
        accent=(180, 120, 72),
    ),
    Slide(
        source="03-site-cretaceous-marl.jpg",
        output="03-site-cretaceous-marl.png",
        headline="Document real\ngeology",
        accent=(212, 175, 55),
    ),
    Slide(
        source="04-fossil-iguanodon.jpg",
        output="04-fossil-iguanodon.png",
        headline="Fossils from\nthe field",
        accent=PRIMARY,
    ),
    Slide(
        source="05-tool-aerial-scout.jpg",
        output="05-tool-aerial-scout.png",
        headline="Tools for\nthe expedition",
        accent=(168, 140, 110),
    ),
    Slide(
        source="06-cladogram-tree.jpg",
        output="06-cladogram-tree.png",
        headline="See how they\nare related",
        accent=SECONDARY,
    ),
    Slide(
        source="07-profile-career.png",
        output="07-profile-career.png",
        headline="Walk. Collect.\nCurate.",
        accent=PRIMARY,
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
            red, green, blue, _alpha = pixels[x, y]
            if red <= threshold and green <= threshold and blue <= threshold:
                pixels[x, y] = (red, green, blue, 0)
    return rgba


def _blend_rect(
    image: Image.Image,
    left: int,
    top: int,
    right: int,
    bottom: int,
) -> Image.Image:
    width, height = image.size
    pad = max(4, (bottom - top + 1) // 8)
    fill_left = max(0, left - pad)
    fill_right = min(width - 1, right + pad)
    fill_top = max(0, top - pad)
    fill_bottom = min(height - 1, bottom + pad)
    sample_left = max(0, fill_left - 10)
    sample_right = min(width - 1, fill_right + 10)
    patched = image.copy()
    patched_px = patched.load()
    span = max(1, fill_right - fill_left)
    for y in range(fill_top, fill_bottom + 1):
        left_color = patched_px[sample_left, y]
        right_color = patched_px[sample_right, y]
        for x in range(fill_left, fill_right + 1):
            t = (x - fill_left) / span
            patched_px[x, y] = tuple(
                int(left_color[i] * (1 - t) + right_color[i] * t) for i in range(3)
            )
    return patched


def _longest_black_run(
    pixels,
    y: int,
    x_min: int,
    x_max: int,
) -> tuple[int, int, int] | None:
    best: tuple[int, int, int] | None = None
    x = x_min
    while x < x_max:
        red, green, blue = pixels[x, y]
        if red < 18 and green < 18 and blue < 18:
            start = x
            x += 1
            while x < x_max:
                red, green, blue = pixels[x, y]
                if red >= 18 or green >= 18 or blue >= 18:
                    break
                x += 1
            run = (x - start, start, x - 1)
            if best is None or run[0] > best[0]:
                best = run
        else:
            x += 1
    return best


def _row_mostly_black(pixels, y: int, left: int, right: int) -> bool:
    dark = 0
    total = right - left + 1
    for x in range(left, right + 1):
        red, green, blue = pixels[x, y]
        if red < 18 and green < 18 and blue < 18:
            dark += 1
    return dark / total >= 0.7


def _neutral_dynamic_island(image: Image.Image) -> Image.Image:
    """Replace a Live Activity / black island with a compact warm-taupe pill."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    idle_w = max(36, round(width * 0.318))
    idle_h = max(16, round(height * 0.034))
    idle_top = max(8, round(height * 0.014))

    search_bottom = max(36, int(height * 0.06))
    x_min = int(width * 0.30)
    x_max = int(width * 0.70)
    best: tuple[int, int, int, int] | None = None
    for y in range(search_bottom):
        run = _longest_black_run(pixels, y, x_min, x_max)
        if run and (best is None or run[0] > best[0]):
            best = (run[0], y, run[1], run[2])

    patched = rgb
    top = idle_top
    if best and best[0] >= width * 0.20:
        _run_len, seed_y, left, right = best
        top = seed_y
        bottom = seed_y
        while top > 0 and _row_mostly_black(pixels, top - 1, left, right):
            top -= 1
        while bottom + 1 < search_bottom and _row_mostly_black(
            pixels, bottom + 1, left, right
        ):
            bottom += 1
        island_w = right - left + 1
        island_h = bottom - top + 1
        if island_w > width * 0.36:
            patched = _blend_rect(rgb, left, top, right, bottom)
            top = idle_top
        else:
            pad = 3
            idle_w = max(idle_w, island_w + pad * 2)
            idle_h = max(idle_h, island_h + pad * 2)
            top = max(0, top - pad)

    return _draw_idle_island(
        patched,
        top=top,
        width_hint=idle_w,
        height_hint=idle_h,
    )


def _draw_idle_island(
    image: Image.Image,
    *,
    top: int,
    width_hint: int | None = None,
    height_hint: int | None = None,
) -> Image.Image:
    width, height = image.size
    pill_h = height_hint if height_hint and 14 <= height_hint <= 64 else max(18, round(height * 0.028))
    pill_w = width_hint if width_hint else max(pill_h, round(width * 0.318))
    pill_x = (width - pill_w) // 2
    pill_y = max(6, top)
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle(
        (pill_x, pill_y, pill_x + pill_w - 1, pill_y + pill_h - 1),
        radius=pill_h // 2,
        fill=ISLAND,
    )
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


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
    canvas.alpha_composite(
        _radial_glow(canvas_size, PRIMARY, (round(160 * sx), round(2720 * sy)), round(780 * sx), 42)
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

    source = _neutral_dynamic_island(Image.open(SOURCE_DIR / slide.source))
    top_band = headline_y + headline_h + max(72, round(120 * sy))
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
    if master.mode != "RGB":
        raise SystemExit(f"{name} must be RGB, got {master.mode}")
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
        _write_outputs(
            compose(slide, IPHONE_CANVAS),
            IPHONE_CANVAS,
            IPHONE_OUTPUTS,
            slide.output,
        )
        _write_outputs(
            compose(slide, IPAD_CANVAS),
            IPAD_CANVAS,
            IPAD_OUTPUTS,
            slide.output,
        )


if __name__ == "__main__":
    main()
