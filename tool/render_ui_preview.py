#!/usr/bin/env python3
"""Renders phone-sized design previews of the RAGAA screens for sign-off.

These are drawn from the same tokens the app uses (navy, turquoise, white,
light grey) and the same Arabic font, so the client can approve the identity
before a build is installed. They are illustrations of the layout, not
screenshots of a running device; the review folder keeps that distinction in
its file names.

Outputs (390x844, one per screen)
---------------------------------
review/ui/preview_home.png     لوحة التحكم       dashboard
review/ui/preview_entry.png    تسجيل التحصيل     full-screen entry
review/ui/preview_reports.png  التقارير          reports and export

Usage:  python3 tool/render_ui_preview.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_icon import render_word  # noqa: E402  (same shaping pipeline)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "review", "ui")

NAVY = (11, 36, 71)
NAVY_DEEP = (7, 26, 51)
TURQUOISE = (20, 184, 166)
TURQUOISE_WASH = (230, 250, 247)
WHITE = (255, 255, 255)
CANVAS = (244, 246, 249)
BORDER = (226, 232, 240)
MUTED = (100, 116, 139)
GREEN = (56, 116, 58)
AMBER = (245, 158, 11)

W, H = 390, 844


def put(img: Image.Image, text: str, px: int, color, x: int, y: int, align="right") -> None:
    """Draws shaped Arabic text, right-aligned by default (the app is RTL)."""
    stamp = render_word(text, px, color)
    if align == "right":
        x = x - stamp.width
    elif align == "center":
        x = x - stamp.width // 2
    img.alpha_composite(stamp, (max(0, int(x)), int(y)))


def card(img: Image.Image, box, radius: int = 18, fill=WHITE, outline=BORDER) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius, fill=fill + (255,), outline=outline + (255,))
    img.alpha_composite(layer)


def bar(img: Image.Image, box, fill) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=8, fill=fill + (255,))
    img.alpha_composite(layer)


def canvas() -> Image.Image:
    img = Image.new("RGBA", (W, H), CANVAS + (255,))
    return img


def header(img: Image.Image, title: str, subtitle: str) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle((0, 0, W, 132), fill=NAVY + (255,))
    img.alpha_composite(layer)
    put(img, title, 30, WHITE, W - 22, 44)
    put(img, subtitle, 15, (168, 191, 214), W - 22, 88)
    # brand chip
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((22, 46, 86, 110), radius=18, fill=TURQUOISE + (255,))
    img.alpha_composite(layer)
    put(img, "رجائى", 30, WHITE, 54, 66, align="center")


def bottom_nav(img: Image.Image, active: int) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle((0, H - 78, W, H), fill=WHITE + (255,))
    d.line((0, H - 78, W, H - 78), fill=BORDER + (255,), width=2)
    labels = ["لوحة التحكم", "التحصيل", "المنافذ", "التقارير", "المزيد"]
    for i, _ in enumerate(labels):
        cx = W - 39 - i * 78
        d.rounded_rectangle(
            (cx - 28, H - 66, cx + 28, H - 44),
            radius=11,
            fill=(TURQUOISE_WASH + (255,)) if i == active else (0, 0, 0, 0),
        )
        d.ellipse((cx - 8, H - 62, cx + 8, H - 46), fill=(TURQUOISE if i == active else MUTED) + (255,))
    # The bar is composited first: text drawn before it would be painted over.
    img.alpha_composite(layer)
    for i, label in enumerate(labels):
        cx = W - 39 - i * 78
        put(img, label, 12, NAVY if i == active else MUTED, cx, H - 34, align="center")


def kpi(img: Image.Image, box, title: str, value: str, accent) -> None:
    card(img, box)
    put(img, title, 13, MUTED, box[2] - 14, box[1] + 14)
    put(img, value, 26, accent, box[2] - 14, box[1] + 42)


def screen_home() -> Image.Image:
    img = canvas()
    header(img, "لوحة التحكم المركزية", "تحديث لحظي لكل المنافذ والورديات")
    kpi(img, (22, 152, 190, 236), "إجمالي التحصيل", "81,900.00", NAVY)
    kpi(img, (200, 152, 368, 236), "إجمالي الموازين", "48,900.00", TURQUOISE)
    kpi(img, (22, 246, 190, 330), "الرسوم اليدوية", "19,450.00", NAVY)
    kpi(img, (200, 246, 368, 330), "الرسوم الآلية", "12,950.00", NAVY)
    card(img, (22, 342, 368, 470))
    put(img, "المنافذ النشطة", 17, NAVY, 354, 356)
    for i, (name, amount) in enumerate([("منفذ الميدان", "37,800.00"), ("منفذ الجامعة", "31,700.00")]):
        y = 392 + i * 36
        put(img, name, 15, (30, 41, 59), 354, y)
        put(img, amount, 15, GREEN, 210, y)
    card(img, (22, 482, 368, 570), fill=NAVY, outline=NAVY)
    put(img, "تسجيل تحصيل وردية", 20, WHITE, 354, 498)
    put(img, "خطوتان فقط: المنفذ ثم المبلغ", 14, (168, 191, 214), 354, 532)
    card(img, (22, 582, 368, 720))
    put(img, "آخر التحصيلات", 16, NAVY, 354, 594)
    for i, (line, amount) in enumerate(
        [("منفذ الميدان — صباحية", "12,400.00"), ("منفذ الجامعة — مسائية", "9,800.00")]
    ):
        y = 626 + i * 34
        put(img, line, 13, (30, 41, 59), 354, y)
        put(img, amount, 13, GREEN, 190, y)
    bottom_nav(img, 0)
    return img


def screen_entry() -> Image.Image:
    img = canvas()
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle((0, 0, W, 74), fill=WHITE + (255,))
    img.alpha_composite(layer)
    put(img, "تسجيل تحصيل وردية", 21, NAVY, W - 24, 24)
    put(img, "‹", 26, MUTED, 24, 20, align="left")

    card(img, (14, 88, 376, 250))
    put(img, "الوردية والمنفذ", 15, NAVY, 360, 100)
    for i, (label, value) in enumerate(
        [("المنفذ", "منفذ الميدان (٣ ورديات)"), ("الوردية", "الوردية الصباحية")]
    ):
        y = 128 + i * 44
        card(img, (28, y, 362, y + 34), radius=10, fill=CANVAS, outline=BORDER)
        put(img, value, 14, (30, 41, 59), 350, y + 9)
    bar(img, (28, 212, 150, 240), TURQUOISE_WASH)
    put(img, "اليوم", 14, NAVY, 58, 217, align="left")
    bar(img, (160, 212, 214, 240), CANVAS)
    put(img, "أمس", 13, MUTED, 206, 218)

    card(img, (14, 262, 376, 560))
    put(img, "المبالغ", 15, NAVY, 360, 274)
    put(img, "إجمالي مبلغ التحصيل (ج.م)", 13, MUTED, 360, 300)
    put(img, "1,500.50", 40, NAVY, 360, 320)
    for i, (label, value) in enumerate(
        [("الرسوم اليدوية", "300.00"), ("الرسوم الآلية", "200.25"), ("إجمالي الرسوم", "500.25")]
    ):
        y = 386 + i * 40
        put(img, label, 14, MUTED, 360, y + 8)
        card(img, (28, y, 200, y + 34), radius=10, fill=CANVAS, outline=BORDER)
        put(img, value, 14, (30, 41, 59), 190, y + 9)
    card(img, (28, 508, 362, 548), radius=14, fill=TURQUOISE_WASH, outline=TURQUOISE)
    put(img, "إجمالي الموازين (محسوب)", 12, TURQUOISE, 350, 513)
    put(img, "1,000.25", 18, NAVY, 350, 528)

    card(img, (14, 572, 376, 654))
    put(img, "ملاحظات وتوثيق", 15, NAVY, 360, 584)
    card(img, (28, 610, 362, 642), radius=10, fill=CANVAS, outline=BORDER)
    put(img, "ملاحظات (اختياري)", 13, MUTED, 350, 618)

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle((0, 668, W, H), fill=WHITE + (255,))
    d.line((0, 668, W, 668), fill=BORDER + (255,), width=2)
    d.rounded_rectangle((150, 700, 368, 754), radius=16, fill=NAVY + (255,))
    img.alpha_composite(layer)
    put(img, "إجمالي الموازين", 12, MUTED, 130, 686)
    put(img, "1,000.25", 17, NAVY, 130, 704)
    put(img, "حفظ التحصيل", 18, WHITE, 259, 716, align="center")
    return img


def screen_reports() -> Image.Image:
    img = canvas()
    header(img, "التقارير", "الفترة: يوم واحد — كل المنافذ")
    bar(img, (22, 150, 122, 184), TURQUOISE_WASH)
    put(img, "اليوم", 14, NAVY, 112, 156)
    card(img, (134, 150, 234, 184), radius=10, fill=WHITE, outline=BORDER)
    put(img, "أمس", 14, MUTED, 224, 156)
    card(img, (246, 150, 368, 184), radius=10, fill=WHITE, outline=BORDER)
    put(img, "اختيار تاريخ", 14, MUTED, 356, 156)

    card(img, (22, 198, 368, 300))
    put(img, "ملخص الفترة", 16, NAVY, 352, 210)
    for i, (label, value) in enumerate(
        [("إجمالي التحصيل", "81,900.00"), ("إجمالي الموازين", "48,900.00")]
    ):
        y = 240 + i * 30
        put(img, label, 14, MUTED, 352, y)
        put(img, value, 15, GREEN, 220, y)

    for i, (latin, fill) in enumerate([("PDF", NAVY), ("Excel", TURQUOISE)]):
        x2 = 368 - i * 182
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle((x2 - 168, 316, x2, 372), radius=14, fill=fill + (255,))
        img.alpha_composite(layer)
        put(img, "تصدير", 17, WHITE, x2 - 18, 334)
        put(img, latin, 15, WHITE, x2 - 122, 336, align="left")

    card(img, (22, 390, 368, 492), radius=16, fill=(236, 253, 245), outline=(167, 243, 208))
    put(img, "تم حفظ الملف", 15, GREEN, 352, 402)
    put(img, "Download", 12, (4, 120, 87), 300, 428)
    put(img, "ragaa_day.pdf", 12, (4, 120, 87), 92, 428, align="left")
    bar(img, (250, 452, 352, 482), (209, 250, 229))
    put(img, "فتح الملف", 13, NAVY, 342, 458)
    put(img, "مشاركة", 13, GREEN, 236, 458)

    card(img, (22, 506, 368, 640))
    put(img, "تقرير المنافذ", 16, NAVY, 352, 518)
    for i, (name, amount) in enumerate(
        [("منفذ الميدان", "37,800"), ("منفذ الجامعة", "31,700"), ("منفذ السوق", "12,400")]
    ):
        y = 552 + i * 28
        put(img, name, 14, (30, 41, 59), 352, y)
        put(img, amount, 14, GREEN, 220, y)
    card(img, (22, 654, 368, 736))
    put(img, "تصدير اليومية", 14, NAVY, 352, 666)
    put(img, "خطوط الجدول كما في الدفتر الورقي", 12, MUTED, 352, 694)
    bottom_nav(img, 3)
    return img


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, builder in [
        ("preview_home.png", screen_home),
        ("preview_entry.png", screen_entry),
        ("preview_reports.png", screen_reports),
    ]:
        image = builder().convert("RGB")
        path = os.path.join(OUT, name)
        image.save(path)
        print("wrote", os.path.relpath(path, ROOT), image.size)


if __name__ == "__main__":
    main()
