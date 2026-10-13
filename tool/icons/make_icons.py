#!/usr/bin/env python3
"""Draw the app icon (a remote's D-pad) and write every size Android and iOS need.

  python3 tool/icons/make_icons.py

Requires Pillow. Output paths are relative to the project root.
"""

from __future__ import annotations

import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BG_TOP = (24, 28, 36)
BG_BOTTOM = (10, 12, 16)
RING = (236, 238, 242)
ARROW = (42, 46, 55)
OK = (27, 30, 37)
ACCENT = (79, 209, 197)
SS = 4  # supersampling factor


def _gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM))
        for x in range(size):
            px[x, y] = color
    return img


def _dpad(size: int, art_fraction: float) -> Image.Image:
    """Transparent layer with the D-pad centred, its diameter = art_fraction * size."""
    s = size * SS
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c = s / 2
    r = s * art_fraction / 2

    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((c - r, c - r + r * 0.06, c + r, c + r + r * 0.06), fill=(0, 0, 0, 140))
    layer = Image.alpha_composite(layer, shadow.filter(ImageFilter.GaussianBlur(r * 0.08)))

    d = ImageDraw.Draw(layer)
    d.ellipse((c - r, c - r, c + r, c + r), fill=RING)
    ok_r = r * 0.43
    d.ellipse((c - ok_r, c - ok_r, c + ok_r, c + ok_r), fill=OK)
    dot = ok_r * 0.28
    d.ellipse((c - dot, c - dot, c + dot, c + dot), fill=ACCENT)

    dist = (r + ok_r) / 2
    half = r * 0.11
    width = max(1, round(r * 0.075))
    for angle in (-math.pi / 2, math.pi / 2, math.pi, 0.0):
        ux, uy = math.cos(angle), math.sin(angle)
        tip = (c + ux * (dist + half * 0.55), c + uy * (dist + half * 0.55))
        back = (ux * half * 1.1, uy * half * 1.1)
        side = (-uy * half * 1.3, ux * half * 1.3)
        p1 = (tip[0] - back[0] + side[0], tip[1] - back[1] + side[1])
        p2 = (tip[0] - back[0] - side[0], tip[1] - back[1] - side[1])
        d.line([p1, tip, p2], fill=ARROW, width=width, joint="curve")
        for p in (p1, tip, p2):
            d.ellipse((p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2), fill=ARROW)
    return layer.resize((size, size), Image.LANCZOS)


def full_icon(size: int, rounded: bool) -> Image.Image:
    base = _gradient(size).convert("RGBA")
    icon = Image.alpha_composite(base, _dpad(size, 0.66))
    if not rounded:
        return icon.convert("RGB")  # iOS applies its own mask and forbids alpha
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), radius=size * SS * 0.22, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask.resize((size, size), Image.LANCZOS))
    return out


def save(img: Image.Image, rel: str) -> None:
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def main() -> None:
    android = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = "android/app/src/main/res"
    for name, density in android.items():
        save(full_icon(round(48 * density), rounded=True), f"{res}/mipmap-{name}/ic_launcher.png")
        # Adaptive icon foreground: 108dp canvas, art inside the 66dp safe zone.
        save(_dpad(round(108 * density), 0.42), f"{res}/drawable-{name}/ic_launcher_foreground.png")

    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    entries = [
        ("20x20", "2x", "iphone"), ("20x20", "3x", "iphone"),
        ("29x29", "1x", "iphone"), ("29x29", "2x", "iphone"), ("29x29", "3x", "iphone"),
        ("40x40", "2x", "iphone"), ("40x40", "3x", "iphone"),
        ("60x60", "2x", "iphone"), ("60x60", "3x", "iphone"),
        ("20x20", "1x", "ipad"), ("20x20", "2x", "ipad"),
        ("29x29", "1x", "ipad"), ("29x29", "2x", "ipad"),
        ("40x40", "1x", "ipad"), ("40x40", "2x", "ipad"),
        ("76x76", "1x", "ipad"), ("76x76", "2x", "ipad"),
        ("83.5x83.5", "2x", "ipad"),
        ("1024x1024", "1x", "ios-marketing"),
    ]
    images = []
    for size, scale, idiom in entries:
        filename = f"Icon-App-{size}@{scale}.png"
        pixels = round(float(size.split("x")[0]) * int(scale[0]))
        save(full_icon(pixels, rounded=False), f"{ios_dir}/{filename}")
        images.append({"size": size, "idiom": idiom, "filename": filename, "scale": scale})
    with open(os.path.join(ROOT, ios_dir, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
        f.write("\n")

    save(full_icon(512, rounded=True), "tool/icons/icon-512.png")


if __name__ == "__main__":
    main()
