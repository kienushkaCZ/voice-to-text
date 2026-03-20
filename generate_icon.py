#!/usr/bin/env python3
"""Generate a macOS app icon for Voice-to-Text."""

import math
import os
import subprocess
from PIL import Image, ImageDraw

def create_icon(size):
    """Create a single icon at the given size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    s = size  # shorthand
    margin = s * 0.08

    # --- Rounded rectangle background with gradient ---
    # Create gradient: deep blue-violet to teal
    for y in range(size):
        t = y / size
        # Top: #4A1A8A (purple) -> Bottom: #0D7377 (teal)
        r = int(74 * (1 - t) + 13 * t)
        g = int(26 * (1 - t) + 115 * t)
        b = int(138 * (1 - t) + 119 * t)
        for x in range(size):
            img.putpixel((x, y), (r, g, b, 255))

    # Apply rounded rectangle mask
    corner_r = s * 0.22
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [margin, margin, s - margin, s - margin],
        radius=corner_r,
        fill=255
    )
    img.putalpha(mask)

    # --- Draw microphone ---
    cx = s * 0.45  # slightly left of center to make room for waves
    cy = s * 0.42

    mic_w = s * 0.14  # mic body width
    mic_h = s * 0.24  # mic body height
    mic_r = mic_w / 2  # rounded top

    white = (255, 255, 255, 240)
    white_soft = (255, 255, 255, 160)
    white_faint = (255, 255, 255, 80)

    # Mic body (rounded rectangle)
    mic_left = cx - mic_w / 2
    mic_right = cx + mic_w / 2
    mic_top = cy - mic_h / 2
    mic_bottom = cy + mic_h / 2

    draw.rounded_rectangle(
        [mic_left, mic_top, mic_right, mic_bottom],
        radius=mic_r,
        fill=white
    )

    # Mic grille lines
    line_w = max(1, s // 200)
    grille_color = (100, 50, 160, 120)
    for i in range(3):
        ly = mic_top + mic_h * (0.3 + i * 0.15)
        draw.line(
            [mic_left + mic_w * 0.2, ly, mic_right - mic_w * 0.2, ly],
            fill=grille_color,
            width=line_w
        )

    # Mic holder arc (U shape below mic)
    arc_margin = s * 0.04
    arc_box = [
        mic_left - arc_margin,
        mic_bottom - mic_h * 0.4,
        mic_right + arc_margin,
        mic_bottom + s * 0.1
    ]
    arc_w = max(2, int(s * 0.02))
    draw.arc(arc_box, 0, 180, fill=white, width=arc_w)

    # Mic stand (vertical line + base)
    stand_top = mic_bottom + s * 0.1
    stand_bottom = stand_top + s * 0.08
    draw.line(
        [cx, stand_top, cx, stand_bottom],
        fill=white,
        width=arc_w
    )
    # Base
    base_w = s * 0.1
    draw.line(
        [cx - base_w / 2, stand_bottom, cx + base_w / 2, stand_bottom],
        fill=white,
        width=arc_w
    )

    # --- Sound waves (right side) ---
    wave_cx = cx + s * 0.02
    wave_cy = cy

    for i, (radius, alpha) in enumerate([(s * 0.16, 180), (s * 0.24, 120), (s * 0.32, 70)]):
        wave_color = (255, 255, 255, alpha)
        wave_w = max(2, int(s * 0.018))
        box = [
            wave_cx - radius,
            wave_cy - radius,
            wave_cx + radius,
            wave_cy + radius
        ]
        draw.arc(box, -45, 45, fill=wave_color, width=wave_w)

    # --- Subtle "T" text indicator (bottom right, small) ---
    # Small text cursor / "Aa" to hint at text output
    tx = s * 0.7
    ty = s * 0.65
    text_h = s * 0.1
    text_w = s * 0.02
    cursor_color = (255, 255, 255, 200)

    # Text cursor blinking line
    draw.line(
        [tx, ty, tx, ty + text_h],
        fill=cursor_color,
        width=max(2, int(s * 0.015))
    )
    # Small horizontal lines (representing text)
    for j in range(3):
        lx = tx + s * 0.03
        ly = ty + j * s * 0.035
        lw = s * (0.12 - j * 0.02)
        line_alpha = 200 - j * 50
        draw.line(
            [lx, ly, lx + lw, ly],
            fill=(255, 255, 255, line_alpha),
            width=max(1, int(s * 0.012))
        )

    return img


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    iconset_dir = os.path.join(script_dir, "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    # Required sizes for macOS .icns
    sizes = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    for base_size, scale in sizes:
        px = base_size * scale
        img = create_icon(px)
        suffix = f"@2x" if scale == 2 else ""
        filename = f"icon_{base_size}x{base_size}{suffix}.png"
        filepath = os.path.join(iconset_dir, filename)
        img.save(filepath, "PNG")
        print(f"  Created {filename} ({px}x{px})")

    # Convert to .icns
    icns_path = os.path.join(script_dir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"\nIcon created: {icns_path}")

    # Cleanup
    import shutil
    shutil.rmtree(iconset_dir)


if __name__ == "__main__":
    main()
