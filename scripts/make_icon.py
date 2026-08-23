#!/usr/bin/env python3
"""Generate the 1024x1024 app icon. Run once; commit the PNG.

    python -m pip install --user pillow
    python scripts/make_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(__file__).resolve().parents[1] / "ios/Sources/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main() -> None:
    top, bottom = (11, 15, 30), (34, 32, 74)
    img = Image.new("RGB", (SIZE, SIZE), top)
    px = img.load()
    for y in range(SIZE):
        row = lerp(top, bottom, y / (SIZE - 1))
        for x in range(SIZE):
            px[x, y] = row

    # Soft glow behind the glyph, offset up-left like light through glass.
    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((160, 120, 760, 720), fill=(143, 168, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(140))
    img = Image.blend(img, Image.composite(glow, img, glow.convert("L")), 0.55)

    draw = ImageDraw.Draw(img, "RGBA")
    # A "backdrop" frame sitting behind the play glyph.
    draw.rounded_rectangle((232, 292, 792, 732), radius=64, outline=(255, 255, 255, 70), width=10)
    # Play triangle, optically centred (shifted right a touch).
    cx, cy, r = 540, 512, 170
    tri = [(cx - r * 0.8, cy - r), (cx - r * 0.8, cy + r), (cx + r * 1.05, cy)]
    draw.polygon(tri, fill=(255, 255, 255, 235))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "PNG")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
