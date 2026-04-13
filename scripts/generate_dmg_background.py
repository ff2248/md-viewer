#!/usr/bin/env python3
"""Generate a DMG installer background image.

Technical requirements for macOS 26 (Tahoe) Finder:
  - 144 DPI (retina @2x)
  - RGBA PNG
  - Placed in .background/ folder inside the DMG volume

Anti-aliasing: draws at 4x resolution then downscales with LANCZOS.
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

# Final output: 1320x800 at 144 DPI (= 660x400 logical Finder window)
FINAL_W, FINAL_H = 1320, 800
SCALE = 4  # Supersample factor for anti-aliasing
W, H = FINAL_W * SCALE, FINAL_H * SCALE
DPI = 144
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "dmg-background.png")

# Colors
BG_COLOR = (246, 248, 252, 255)
ARROW_COLOR = (41, 98, 255, 255)
TEXT_COLOR = ARROW_COLOR


def draw_background(draw):
    draw.rectangle([(0, 0), (W, H)], fill=BG_COLOR)
    # Subtle curved line at the bottom
    for x in range(W):
        t = x / W
        y = int(H - 300 + 120 * math.sin(t * math.pi))
        draw.line([(x, y), (x, y + 6)], fill=(225, 230, 240, 255))


def draw_curved_arrow(draw):
    """Smooth curved arrow between icon positions."""
    start_x, end_x = 1300, 3900
    base_y = 1800
    peak_drop = 500

    # Generate smooth curve points
    points = []
    steps = 200
    for i in range(steps + 1):
        t = i / steps
        x = start_x + (end_x - start_x) * t
        y = base_y + peak_drop * math.sin(t * math.pi) * (0.7 - t * 0.5)
        points.append((x, y))

    # Draw as overlapping circles (stop before arrowhead to avoid double-fill blob)
    r = 18
    HEAD_OVERLAP = 15  # points to skip before arrowhead
    for p in points[:-HEAD_OVERLAP]:
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=ARROW_COLOR)

    # Arrowhead
    tip = points[-1]
    prev = points[-6]
    angle = math.atan2(tip[1] - prev[1], tip[0] - prev[0])
    head_len = 160
    HEAD_SPREAD = 0.42  # radians (~24 degrees)

    p1 = (
        tip[0] - head_len * math.cos(angle - HEAD_SPREAD),
        tip[1] - head_len * math.sin(angle - HEAD_SPREAD),
    )
    p2 = (
        tip[0] - head_len * math.cos(angle + HEAD_SPREAD),
        tip[1] - head_len * math.sin(angle + HEAD_SPREAD),
    )
    draw.polygon([tip, p1, p2], fill=ARROW_COLOR)


def draw_text(draw):
    font_size = 220
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFCompact.ttf", font_size)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            print("  WARNING: system fonts not found, using fallback bitmap font")
            font = ImageFont.load_default()

    text = "drag and drop"
    bbox = draw.textbbox((0, 0), text, font=font)
    x = (W - (bbox[2] - bbox[0])) / 2
    draw.text((x, 1200), text, fill=TEXT_COLOR, font=font)


def main():
    # Draw at 4x resolution
    img = Image.new("RGBA", (W, H), BG_COLOR)
    draw = ImageDraw.Draw(img)

    draw_background(draw)
    draw_text(draw)
    draw_curved_arrow(draw)

    # Downscale with LANCZOS for smooth anti-aliasing
    img = img.resize((FINAL_W, FINAL_H), Image.LANCZOS)

    img.save(OUT, dpi=(DPI, DPI))
    size_kb = os.path.getsize(OUT) // 1024
    print(f"  {OUT} ({FINAL_W}x{FINAL_H}, {DPI} DPI, {size_kb} KB)")


if __name__ == "__main__":
    main()
