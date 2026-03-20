#!/usr/bin/env python3
"""Generate MDViewer app icon - a clean document icon with 'MD' text."""

from PIL import Image, ImageDraw, ImageFont
import os
import json

SIZE = 1024
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "MDViewer", "Assets.xcassets", "AppIcon.appiconset")


def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = size * 0.08
    w = size - 2 * margin
    h = size - 2 * margin
    x0, y0 = margin, margin
    corner = size * 0.12

    # Document shape with folded corner
    fold = size * 0.22
    doc_points = [
        (x0 + corner, y0),                    # top-left after corner
        (x0 + w - fold, y0),                  # top-right before fold
        (x0 + w, y0 + fold),                  # fold bottom
        (x0 + w, y0 + h - corner),            # bottom-right before corner
        (x0 + w - corner, y0 + h),            # bottom-right after corner
        (x0 + corner, y0 + h),                # bottom-left after corner
        (x0, y0 + h - corner),                # bottom-left before corner
        (x0, y0 + corner),                    # top-left before corner
    ]

    # Shadow
    shadow_offset = size * 0.015
    shadow_points = [(p[0] + shadow_offset, p[1] + shadow_offset) for p in doc_points]
    draw.polygon(shadow_points, fill=(0, 0, 0, 40))

    # Document background - soft white with slight gradient effect
    draw.polygon(doc_points, fill=(255, 255, 255, 255), outline=(200, 200, 200, 255), width=max(1, size // 200))

    # Folded corner triangle
    fold_points = [
        (x0 + w - fold, y0),
        (x0 + w, y0 + fold),
        (x0 + w - fold, y0 + fold),
    ]
    draw.polygon(fold_points, fill=(230, 230, 235, 255), outline=(200, 200, 200, 255), width=max(1, size // 200))

    # "MD" text - bold, centered, in a nice blue
    font_size = int(size * 0.28)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFCompact.ttf", font_size)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

    text = "MD"
    text_color = (41, 98, 255, 255)  # Vibrant blue

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = x0 + (w - tw) / 2
    ty = y0 + fold + (h - fold - th) / 2 - size * 0.02

    draw.text((tx, ty), text, fill=text_color, font=font)

    # Decorative lines (like markdown content lines)
    line_color = (200, 210, 220, 180)
    line_y_start = ty + th + size * 0.06
    line_x_left = x0 + size * 0.15
    line_x_right = x0 + w - size * 0.15
    line_height = max(2, size // 150)

    for i in range(3):
        ly = line_y_start + i * size * 0.045
        # Vary line lengths
        lx_end = line_x_right - (i % 2) * size * 0.12
        if ly < y0 + h - size * 0.1:
            draw.rounded_rectangle(
                [(line_x_left, ly), (lx_end, ly + line_height)],
                radius=line_height,
                fill=line_color,
            )

    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # Generate icon sizes needed for macOS
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    icon = draw_icon(SIZE)

    images = []
    for s in sizes:
        resized = icon.resize((s, s), Image.LANCZOS)
        filename = f"icon_{s}x{s}.png"
        resized.save(os.path.join(OUT_DIR, filename))
        images.append({"size": f"{s}x{s}", "filename": filename, "scale": "1x"})
        print(f"  {filename}")

        # @2x versions for smaller sizes
        if s <= 512:
            s2 = s * 2
            resized2 = icon.resize((s2, s2), Image.LANCZOS)
            filename2 = f"icon_{s}x{s}@2x.png"
            resized2.save(os.path.join(OUT_DIR, filename2))
            images.append({"size": f"{s}x{s}", "filename": filename2, "scale": "2x"})
            print(f"  {filename2}")

    # Write Contents.json
    contents = {
        "images": [
            {"filename": img["filename"], "idiom": "mac", "scale": img["scale"], "size": img["size"]}
            for img in images
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("Contents.json updated")


if __name__ == "__main__":
    main()
