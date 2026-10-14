#!/usr/bin/env python3
"""
Generates high-resolution macOS application icons and crisp status bar template icons
for "Shots" based directly on the user's marquee frame & cursive exclamation mark design.
"""

import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def generate_icons():
    resources_dir = "Resources"
    os.makedirs(resources_dir, exist_ok=True)

    # 1. Load clean reference symbol
    ref_path = "/Users/citizen/.gemini/antigravity-ide/brain/fbe3bee5-2603-45fc-8272-9ca62fbee606/.user_uploaded/media_1791831567586.png"
    if os.path.exists(ref_path):
        ref = Image.open(ref_path).convert("L")
        w, h = ref.size
        # Isolate foreground symbol inside the card area
        clean_mask = Image.new("L", (w, h), 0)
        for y in range(22, 160):
            for x in range(25, 150):
                if ref.getpixel((x, y)) < 128:
                    clean_mask.putpixel((x, y), 255)
        bbox = clean_mask.getbbox()
        symbol = clean_mask.crop(bbox)
    elif os.path.exists(os.path.join(resources_dir, "clean_symbol.png")):
        symbol = Image.open(os.path.join(resources_dir, "clean_symbol.png")).convert("L")
    else:
        raise FileNotFoundError("Reference symbol not found")

    cw, ch = symbol.size

    # =========================================================================
    # 2. macOS Master AppIcon (1024x1024, supersampled 4x = 4096)
    # =========================================================================
    ss = 4
    canvas_size = 1024 * ss
    master = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    tile_size = int(824 * ss)
    tile_margin = (canvas_size - tile_size) // 2
    tile_radius = int(185 * ss)

    # Multi-stage drop shadows
    amb_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    amb_draw = ImageDraw.Draw(amb_shadow)
    amb_offset_y = int(32 * ss)
    amb_box = [
        tile_margin,
        tile_margin + amb_offset_y,
        tile_margin + tile_size,
        tile_margin + tile_size + amb_offset_y
    ]
    amb_draw.rounded_rectangle(amb_box, radius=tile_radius, fill=(0, 0, 0, 55))
    amb_shadow = amb_shadow.filter(ImageFilter.GaussianBlur(int(36 * ss)))
    master = Image.alpha_composite(master, amb_shadow)

    dir_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    dir_draw = ImageDraw.Draw(dir_shadow)
    dir_offset_y = int(16 * ss)
    dir_box = [
        tile_margin,
        tile_margin + dir_offset_y,
        tile_margin + tile_size,
        tile_margin + tile_size + dir_offset_y
    ]
    dir_draw.rounded_rectangle(dir_box, radius=tile_radius, fill=(0, 0, 0, 65))
    dir_shadow = dir_shadow.filter(ImageFilter.GaussianBlur(int(16 * ss)))
    master = Image.alpha_composite(master, dir_shadow)

    # Sleek dark titanium tile surface
    tile_img = Image.new("RGBA", (tile_size, tile_size))
    for y in range(tile_size):
        ratio = y / tile_size
        r = int(34 - ratio * 18)
        g = int(38 - ratio * 19)
        b = int(48 - ratio * 24)
        for x in range(tile_size):
            tile_img.putpixel((x, y), (r, g, b, 255))

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    tile_box = [tile_margin, tile_margin, tile_margin + tile_size, tile_margin + tile_size]
    mask_draw.rounded_rectangle(tile_box, radius=tile_radius, fill=255)

    composite = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    composite.paste(tile_img, (tile_margin, tile_margin))
    master.paste(composite, (0, 0), mask)

    # Inner metallic hairline border
    border_draw = ImageDraw.Draw(master)
    border_draw.rounded_rectangle(
        tile_box,
        radius=tile_radius,
        outline=(255, 255, 255, 45),
        width=max(1, int(1.5 * ss))
    )

    # Scale symbol onto tile
    symbol_h = int(580 * ss)
    symbol_w = int(cw * (symbol_h / ch))

    symbol_mask = symbol.resize((symbol_w, symbol_h), Image.Resampling.LANCZOS)
    symbol_mask = symbol_mask.filter(ImageFilter.GaussianBlur(int(1.2 * ss)))

    cx = canvas_size // 2
    cy = canvas_size // 2
    off_x = cx - symbol_w // 2
    off_y = cy - symbol_h // 2

    # Drop shadow under glyph
    glyph_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    gs_mask = Image.new("L", (canvas_size, canvas_size), 0)
    gs_mask.paste(symbol_mask, (off_x, off_y + int(12 * ss)))
    glyph_shadow.paste((0, 0, 0, 140), (0, 0), gs_mask)
    glyph_shadow = glyph_shadow.filter(ImageFilter.GaussianBlur(int(14 * ss)))
    master = Image.alpha_composite(master, glyph_shadow)

    # Subtle ambient cyan-white glow
    glow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    gl_mask = Image.new("L", (canvas_size, canvas_size), 0)
    gl_mask.paste(symbol_mask, (off_x, off_y))
    glow.paste((56, 189, 248, 120), (0, 0), gl_mask)
    glow = glow.filter(ImageFilter.GaussianBlur(int(8 * ss)))
    master = Image.alpha_composite(master, glow)

    # Sharp white glyph foreground
    glyph_fg = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    glyph_fg.paste((255, 255, 255, 255), (0, 0), gl_mask)
    master = Image.alpha_composite(master, glyph_fg)

    app_icon_1024 = master.resize((1024, 1024), Image.Resampling.LANCZOS)
    app_icon_1024.save(os.path.join(resources_dir, "AppIcon.png"))
    print("✅ Created Resources/AppIcon.png (1024x1024)")

    # =========================================================================
    # 3. Multi-resolution Apple .icns bundle
    # =========================================================================
    iconset_dir = "/tmp/Shots_AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, filename in sizes:
        resized = app_icon_1024.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))

    icns_path = os.path.join(resources_dir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print("✅ Created Resources/AppIcon.icns")

    # =========================================================================
    # 4. Crisp Status Bar Template Icons (18x18 @1x and 36x36 @2x)
    # =========================================================================
    hires_symbol = symbol.resize((cw * 16, ch * 16), Image.Resampling.LANCZOS)
    hires_symbol = hires_symbol.filter(ImageFilter.GaussianBlur(1.8))

    def render_sb(size, target_h):
        target_w = int(cw * (target_h / ch))
        sb_sym = hires_symbol.resize((target_w, target_h), Image.Resampling.LANCZOS)

        sb_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ox = (size - target_w) // 2
        oy = (size - target_h) // 2

        for y in range(target_h):
            for x in range(target_w):
                a = sb_sym.getpixel((x, y))
                if a > 35:
                    alpha = min(255, int(a * 1.3))
                    sb_img.putpixel((ox + x, oy + y), (0, 0, 0, alpha))
        return sb_img

    sb_36 = render_sb(36, 28)
    sb_18 = render_sb(18, 14)

    sb_18.save(os.path.join(resources_dir, "status-bar-icon.png"))
    sb_18.save(os.path.join(resources_dir, "StatusBarIcon.png"))
    sb_36.save(os.path.join(resources_dir, "status-bar-icon@2x.png"))
    sb_36.save(os.path.join(resources_dir, "StatusBarIcon@2x.png"))
    print("✅ Created crisp Status Bar icons (18x18 & 36x36)")

    # Clean up intermediate test files
    for tmp_file in [
        "Resources/test_app_icon.png",
        "Resources/clean_symbol.png",
        "Resources/ref_cropped.png",
        "Resources/test_sb18.png",
        "Resources/test_sb36.png",
        "Resources/marquee_vector_test.png",
    ]:
        if os.path.exists(tmp_file):
            os.remove(tmp_file)

    print("✅ Completed icon generation pipeline!")

if __name__ == "__main__":
    generate_icons()
