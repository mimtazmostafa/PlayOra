"""Rasterize the PlayNest logo at every Android + iOS launcher size.

This mirrors the Dart `_PlayNestLogoPainter` in
`lib/core/visual_identity/playnest_logo.dart` so the on-device launcher
artwork is byte-identical to the in-app logo seen at startup.

Output:
  android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png
  android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_round.png
  ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png
"""

import os
from pathlib import Path

from PIL import Image, ImageDraw

# Brand palette (matches lib/core/theme/app_colors.dart).
PRIMARY = (0x6C, 0x2B, 0xD9, 255)   # #6C2BD9
ACCENT = (0xFB, 0xBF, 0x24, 255)    # #FBBF24
TILE_BG = (0xFF, 0xFF, 0xFF, 255)   # white tile

# (px, subdir, prefix) for the Android mipmap launcher slots.
# We also emit ic_launcher_round.png for adaptive-icon rounds.
ANDROID_DENSITIES = [
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
]

# iOS universal AppIcon slots (already present in the project).
IOS_SIZES = [
    ("Icon-App-20x20@1x", 20),
    ("Icon-App-20x20@2x", 40),
    ("Icon-App-20x20@3x", 60),
    ("Icon-App-29x29@1x", 29),
    ("Icon-App-29x29@2x", 58),
    ("Icon-App-29x29@3x", 87),
    ("Icon-App-40x40@1x", 40),
    ("Icon-App-40x40@2x", 80),
    ("Icon-App-40x40@3x", 120),
    ("Icon-App-60x60@2x", 120),
    ("Icon-App-60x60@3x", 180),
    ("Icon-App-76x76@1x", 76),
    ("Icon-App-76x76@2x", 152),
    ("Icon-App-83.5x83.5@2x", 167),
    ("Icon-App-1024x1024@1x", 1024),
]


def draw_logo(size: int) -> Image.Image:
    """Render the PlayNest logo at `size` x `size` pixels."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1) Rounded-square tile (white background).
    radius = size * 0.22
    draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)], radius=radius, fill=TILE_BG
    )

    # 2) The "P" — stem (vertical pill) + bowl (upper-half rounded rect).
    #    Geometry normalized to a 1.0 unit space, scaled by `size`.
    stem_w = size * 0.22
    stem_x = size * 0.18
    stem_top = size * 0.14
    stem_height = size * 0.72
    stem_right = stem_x + stem_w
    stem_bottom = stem_top + stem_height

    # Stem (rounded rectangle).
    draw.rounded_rectangle(
        [(stem_x, stem_top), (stem_right, stem_bottom)],
        radius=stem_w / 2,
        fill=PRIMARY,
    )

    # Bowl: upper half, extends from the right of the stem to the right
    # margin, opens downward (rounded bottom).
    bowl_left = stem_x + stem_w * 0.5
    bowl_right = size * 0.84
    bowl_top = size * 0.14
    bowl_bottom = size * 0.58
    bowl_h = bowl_bottom - bowl_top
    bowl_right_pad = bowl_right
    # Draw the bowl as a rectangle, then overlay the play-triangle cutout.
    draw.rounded_rectangle(
        [(bowl_left, bowl_top), (bowl_right_pad, bowl_bottom)],
        radius=bowl_h / 2,
        fill=PRIMARY,
    )

    # 3) Play-triangle cutout (white) — punches the negative space so the
    #    "P" reads as a play button.
    cut_inset = bowl_h * 0.22
    cut_left = bowl_left + bowl_h * 0.12
    cut_right = bowl_right - cut_inset
    cut_mid_y = (bowl_top + bowl_bottom) / 2
    cut_half = bowl_h * 0.28
    draw.polygon(
        [
            (cut_left, cut_mid_y - cut_half),
            (cut_right, cut_mid_y),
            (cut_left, cut_mid_y + cut_half),
        ],
        fill=TILE_BG,
    )

    # 4) Gold dot inside the triangle — punctuates the logo with the
    #    brand accent color.
    inner_cut_left = bowl_left + bowl_h * 0.12
    inner_cut_right = size * 0.84 - bowl_h * 0.22
    inner_cut_mid_y = (bowl_top + bowl_bottom) / 2
    inner_half = bowl_h * 0.16
    draw.polygon(
        [
            (inner_cut_left, inner_cut_mid_y - inner_half),
            (inner_cut_right - inner_half * 0.4, inner_cut_mid_y),
            (inner_cut_left, inner_cut_mid_y + inner_half),
        ],
        fill=ACCENT,
    )

    return img


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    android_res = repo / "android" / "app" / "src" / "main" / "res"
    ios_assets = repo / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

    # Render once at the largest size, then downscale to every slot.
    # Resampling.LANCZOS keeps the gold dot sharp at small sizes.
    master = draw_logo(1024)

    for density, px in ANDROID_DENSITIES:
        out = master.resize((px, px), Image.Resampling.LANCZOS)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            target = android_res / f"mipmap-{density}" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            out.save(target, "PNG")
            print(f"  wrote {target}")

    for name, px in IOS_SIZES:
        out = master.resize((px, px), Image.Resampling.LANCZOS)
        target = ios_assets / f"{name}.png"
        ios_assets.mkdir(parents=True, exist_ok=True)
        out.save(target, "PNG")
        print(f"  wrote {target}")

    print("\nDone.")


if __name__ == "__main__":
    main()
