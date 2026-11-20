#!/usr/bin/env python3
"""Renders the RAGAA (رجائى) brand icon and every platform variant.

The word is shaped with HarfBuzz and rasterised with FreeType so the Arabic
letters join correctly (Pillow alone cannot shape Arabic without libraqm).

Outputs
-------
android/app/src/main/res/mipmap-*/ic_launcher.png          legacy launcher icon
android/app/src/main/res/drawable-*/ic_launcher_foreground  adaptive foreground
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml  adaptive icon
android/app/src/main/res/values/ic_launcher_background.xml  adaptive background
windows/runner/resources/app_icon.ico                       Windows / Inno Setup
assets/branding/app_icon.png                                in-app branding
review/ui/app_icon.png, review/ui/app_icon_48.png           review previews

Usage:  python3 tool/generate_icon.py
"""
from __future__ import annotations

import math
import os

import freetype
import uharfbuzz as hb
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "Tajawal-Bold.ttf")

WORD = "رجائى"

NAVY_TOP = (10, 30, 60)
NAVY_BOTTOM = (16, 58, 96)
TURQUOISE = (20, 184, 166)
WHITE = (255, 255, 255)


# --------------------------------------------------------------------------- #
# Arabic text rendering (HarfBuzz shaping + FreeType rasterisation)
# --------------------------------------------------------------------------- #
def render_word(
    text: str,
    px_height: int,
    color: tuple[int, int, int],
) -> Image.Image:
    """Returns an RGBA image of `text` shaped and rasterised at `px_height`."""
    blob = hb.Blob.from_file_path(FONT_BOLD)
    hb_face = hb.Face(blob)
    hb_font = hb.Font(hb_face)

    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hb_font, buf)

    face = freetype.Face(FONT_BOLD)
    face.set_pixel_sizes(0, px_height)
    scale = px_height / float(hb_face.upem)

    glyphs = []
    pen_x = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        face.load_glyph(info.codepoint, freetype.FT_LOAD_RENDER)
        bitmap = face.glyph.bitmap
        glyphs.append(
            {
                "buffer": bitmap.buffer,
                "width": bitmap.width,
                "rows": bitmap.rows,
                "pitch": bitmap.pitch,
                "left": face.glyph.bitmap_left,
                "top": face.glyph.bitmap_top,
                "x_offset": pos.x_offset * scale,
                "y_offset": pos.y_offset * scale,
                "x_advance": pos.x_advance * scale,
            }
        )
        pen_x += pos.x_advance * scale

    width = int(math.ceil(pen_x)) + px_height
    ascent = int(px_height * 1.05)
    descent = int(px_height * 0.45)
    height = ascent + descent

    mask = Image.new("L", (width, height), 0)
    pen_x = 0.0
    baseline = ascent
    for glyph in glyphs:
        if glyph["width"] and glyph["rows"]:
            glyph_img = Image.frombytes(
                "L",
                (glyph["width"], glyph["rows"]),
                bytes(glyph["buffer"]),
            )
            mask.paste(
                glyph_img,
                (
                    int(round(pen_x + glyph["x_offset"] + glyph["left"])),
                    int(round(baseline - glyph["y_offset"] - glyph["top"])),
                ),
                glyph_img,
            )
        pen_x += glyph["x_advance"]

    bbox = mask.getbbox()
    if bbox:
        mask = mask.crop(bbox)

    result = Image.new("RGBA", mask.size, color + (0,))
    result.putalpha(mask)
    solid = Image.new("RGBA", mask.size, color + (255,))
    solid.putalpha(mask)
    return solid


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=255
    )
    return mask


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        grad.putpixel(
            (0, y),
            tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return grad.resize((size, size))


def build_full_icon(size: int) -> Image.Image:
    """Full launcher icon: navy square, turquoise accent, white word."""
    canvas = vertical_gradient(size, NAVY_TOP, NAVY_BOTTOM).convert("RGBA")

    # Very soft turquoise wash in the lower third: adds depth without noise.
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    radius = int(size * 0.55)
    gd.ellipse(
        (
            size * 0.5 - radius,
            size * 1.05 - radius,
            size * 0.5 + radius,
            size * 1.05 + radius,
        ),
        fill=TURQUOISE + (40,),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    canvas.alpha_composite(glow)

    # Word + accent bar are laid out as one group and centred as a block.
    word = render_word(WORD, int(size * 0.30), WHITE)
    target_w = int(size * 0.68)
    target_h = int(word.height * target_w / word.width)
    word = word.resize((target_w, target_h), Image.LANCZOS)

    bar_w = int(size * 0.24)
    bar_h = max(int(size * 0.028), 3)
    gap = int(size * 0.07)
    block_h = target_h + gap + bar_h
    block_y = (size - block_h) // 2 - int(size * 0.03)
    canvas.alpha_composite(word, ((size - target_w) // 2, block_y))

    bar_mask = Image.new("L", (bar_w, bar_h), 0)
    ImageDraw.Draw(bar_mask).rounded_rectangle(
        (0, 0, bar_w - 1, bar_h - 1), radius=bar_h // 2, fill=255
    )
    canvas.alpha_composite(
        Image.composite(
            Image.new("RGBA", (bar_w, bar_h), TURQUOISE + (255,)),
            Image.new("RGBA", (bar_w, bar_h), (0, 0, 0, 0)),
            bar_mask,
        ),
        ((size - bar_w) // 2, block_y + target_h + gap),
    )

    canvas.putalpha(rounded_mask(size, int(size * 0.22)))
    return canvas


def build_adaptive_foreground(size: int) -> Image.Image:
    """Foreground layer for Android adaptive icons (word inside the safe zone)."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    word = render_word(WORD, int(size * 0.20), WHITE)
    target_w = int(size * 0.45)
    target_h = int(word.height * target_w / word.width)
    word = word.resize((target_w, target_h), Image.LANCZOS)
    word_y = int(size * 0.36)
    canvas.alpha_composite(word, ((size - target_w) // 2, word_y))

    bar_w = int(size * 0.24)
    bar_h = max(int(size * 0.022), 3)
    bar_mask = Image.new("L", (bar_w, bar_h), 0)
    ImageDraw.Draw(bar_mask).rounded_rectangle(
        (0, 0, bar_w - 1, bar_h - 1), radius=bar_h // 2, fill=255
    )
    canvas.alpha_composite(
        Image.composite(
            Image.new("RGBA", (bar_w, bar_h), TURQUOISE + (255,)),
            Image.new("RGBA", (bar_w, bar_h), (0, 0, 0, 0)),
            bar_mask,
        ),
        ((size - bar_w) // 2, word_y + target_h + int(size * 0.035)),
    )
    return canvas


def write(path: str, image: Image.Image) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    print("wrote", os.path.relpath(path, ROOT), image.size)


def main() -> None:
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")

    master = build_full_icon(1024)
    write(os.path.join(ROOT, "assets", "branding", "app_icon.png"), master)
    write(os.path.join(ROOT, "review", "ui", "app_icon.png"), master.resize((512, 512), Image.LANCZOS))
    write(os.path.join(ROOT, "review", "ui", "app_icon_48.png"), master.resize((48, 48), Image.LANCZOS))

    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in legacy.items():
        write(
            os.path.join(res, f"mipmap-{density}", "ic_launcher.png"),
            master.resize((px, px), Image.LANCZOS),
        )

    foreground = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for density, px in foreground.items():
        write(
            os.path.join(res, f"drawable-{density}", "ic_launcher_foreground.png"),
            build_adaptive_foreground(px),
        )

    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
    path = os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(adaptive_xml)
    print("wrote", os.path.relpath(path, ROOT))

    values_dir = os.path.join(res, "values")
    os.makedirs(values_dir, exist_ok=True)
    with open(os.path.join(values_dir, "ic_launcher_background.xml"), "w", encoding="utf-8") as handle:
        handle.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            '    <color name="ic_launcher_background">#0B2447</color>\n'
            "</resources>\n"
        )
    print("wrote android/app/src/main/res/values/ic_launcher_background.xml")

    ico_path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    master.save(
        ico_path,
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("wrote", os.path.relpath(ico_path, ROOT))


if __name__ == "__main__":
    main()
