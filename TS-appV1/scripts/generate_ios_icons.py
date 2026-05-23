#!/usr/bin/env python3
"""Tạo bộ icon iOS placeholder (1024 + các size) nếu chưa có — dùng trên GitHub Actions / Mac."""
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("Cần Pillow: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

SIZES = {
    "Icon-App-20x20@2x.png": (40, 40),
    "Icon-App-20x20@3x.png": (60, 60),
    "Icon-App-29x29@1x.png": (29, 29),
    "Icon-App-29x29@2x.png": (58, 58),
    "Icon-App-29x29@3x.png": (87, 87),
    "Icon-App-40x40@1x.png": (40, 40),
    "Icon-App-40x40@2x.png": (80, 80),
    "Icon-App-40x40@3x.png": (120, 120),
    "Icon-App-60x60@2x.png": (120, 120),
    "Icon-App-60x60@3x.png": (180, 180),
    "Icon-App-20x20@1x.png": (20, 20),
    "Icon-App-76x76@1x.png": (76, 76),
    "Icon-App-76x76@2x.png": (152, 152),
    "Icon-App-83.5x83.5@2x.png": (167, 167),
    "Icon-App-1024x1024@1x.png": (1024, 1024),
}


def render_base(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), (0, 102, 153))
    draw = ImageDraw.Draw(img)
    margin = max(4, size // 16)
    draw.rectangle([margin, margin, size - margin, size - margin], outline=(255, 255, 255), width=max(2, size // 64))
    label = "TS"
    try:
        font = ImageFont.truetype("Arial Bold.ttf", size // 3)
    except OSError:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((size - tw) / 2, (size - th) / 2 - size * 0.05), label, fill=(255, 255, 255), font=font)
    return img


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    base = render_base(1024)
    for name, (w, h) in SIZES.items():
        out = ICONSET / name
        if out.exists():
            continue
        base.resize((w, h), Image.Resampling.LANCZOS).save(out, format="PNG")
        print(f"created {out.name}")


if __name__ == "__main__":
    main()
