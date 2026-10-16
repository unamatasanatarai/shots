#!/usr/bin/env python3
"""
Generates high-resolution macOS application icons, multi-resolution Apple .icns bundles,
crisp status bar template icons, and vector SVG assets for "Shots" featuring:
- Outside squircle tile shape identical to the user's reference cushion artwork
- Rich amber-gold gradient tile (#FABB42 -> #AB6400)
- Tactile 3D white pill/tube slanted 'H' glyph with realistic depth and lighting
- Multi-stage Apple HIG ambient & directional drop shadows
"""

import os
import shutil
import subprocess
from PIL import Image, ImageChops, ImageDraw, ImageFilter


def extract_tile_shape_mask(tile_ref_path):
    """
    Extracts the exact outside squircle cushion tile mask from the reference
    artwork with full 2D subpixel edge anti-aliasing.
    """
    im = Image.open(tile_ref_path).convert("RGBA")
    w, h = im.size

    mask_solid = Image.new("L", (w, h), 0)
    for y in range(54, 642):
        row = [im.getpixel((x, y)) for x in range(w)]
        left_x, right_x = None, None
        for x in range(w):
            r, g, b, _ = row[x]
            if (r > 90 and r > b + 15) or (r > 190 and g > 180 and b > 180):
                left_x = x
                break
        for x in range(w - 1, -1, -1):
            r, g, b, _ = row[x]
            if (r > 90 and r > b + 15) or (r > 190 and g > 180 and b > 180):
                right_x = x
                break
        if left_x is not None and right_x is not None and left_x <= right_x:
            for x in range(left_x, right_x + 1):
                mask_solid.putpixel((x, y), 255)

    # Smooth top and bottom boundaries
    for x in range(w):
        col = [mask_solid.getpixel((x, y)) for y in range(h)]
        if any(c == 255 for c in col):
            top_y = col.index(255)
            bot_y = len(col) - 1 - col[::-1].index(255)
            for dy in range(1, 4):
                if top_y - dy >= 0:
                    r, g, b, _ = im.getpixel((x, top_y - dy))
                    if r > 35:
                        a = max(0, min(255, int((r - 30) / (120 - 30) * 255)))
                        mask_solid.putpixel((x, top_y - dy), max(mask_solid.getpixel((x, top_y - dy)), a))
            for dy in range(1, 4):
                if bot_y + dy < h:
                    r, g, b, _ = im.getpixel((x, bot_y + dy))
                    if r > 35:
                        a = max(0, min(255, int((r - 30) / (120 - 30) * 255)))
                        mask_solid.putpixel((x, bot_y + dy), max(mask_solid.getpixel((x, bot_y + dy)), a))

    sq_bbox = mask_solid.getbbox()
    return mask_solid.crop(sq_bbox)


def extract_glyph_mask(badge_ref_path):
    """
    Extracts the inner stylized slanted 'H' glyph mask from the reference badge artwork.
    """
    orig = Image.open(badge_ref_path).convert("RGBA")
    gray = orig.convert("L")

    # In (375, 155, 645, 415), background is ~233 and glyph is ~33
    glyph_im = Image.new("L", (645 - 375, 415 - 155), 0)
    for y in range(glyph_im.height):
        for x in range(glyph_im.width):
            val = gray.getpixel((375 + x, 155 + y))
            if val <= 33:
                a = 255
            elif val >= 230:
                a = 0
            else:
                a = max(0, min(255, int(round((230 - val) / (230 - 33) * 255))))
            glyph_im.putpixel((x, y), a)

    g_bbox = glyph_im.getbbox()
    return glyph_im.crop(g_bbox)


def generate_icons():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    resources_dir = os.path.join(repo_root, "Resources")
    os.makedirs(resources_dir, exist_ok=True)

    # 1. Resolve tile shape reference
    tile_ref_candidates = [
        os.path.join(resources_dir, "reference_tile_shape.png"),
        "/Users/citizen/.gemini/antigravity-ide/brain/4342d847-49bc-412d-8b73-b4b6b3ae52eb/.user_uploaded/media_1792188371643.png",
    ]
    tile_ref_path = None
    for cand in tile_ref_candidates:
        if os.path.exists(cand):
            tile_ref_path = cand
            break

    if not tile_ref_path:
        raise FileNotFoundError(f"Tile shape reference not found in: {tile_ref_candidates}")

    target_tile_ref = os.path.join(resources_dir, "reference_tile_shape.png")
    if tile_ref_path != target_tile_ref:
        shutil.copyfile(tile_ref_path, target_tile_ref)

    # 2. Resolve glyph badge reference
    badge_ref_candidates = [
        os.path.join(resources_dir, "reference_badge.png"),
        "/Users/citizen/.gemini/antigravity-ide/brain/4342d847-49bc-412d-8b73-b4b6b3ae52eb/.user_uploaded/media_1792187450420.png",
    ]
    badge_ref_path = None
    for cand in badge_ref_candidates:
        if os.path.exists(cand):
            badge_ref_path = cand
            break

    if not badge_ref_path:
        raise FileNotFoundError(f"Badge reference not found in: {badge_ref_candidates}")

    sq_mask = extract_tile_shape_mask(target_tile_ref)
    glyph_mask = extract_glyph_mask(badge_ref_path)
    print(f"Loaded identical tile mask ({sq_mask.size}) and slanted H glyph mask ({glyph_mask.size})")

    # =========================================================================
    # 3. macOS Master AppIcon (1024x1024, supersampled at 2048x2048)
    # =========================================================================
    ss = 2
    canvas_size = 1024 * ss
    master = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    # macOS HIG standard squircle tile: 824x824 points on 1024 canvas
    tile_size = int(824 * ss)
    tile_margin = (canvas_size - tile_size) // 2

    tile_mask = sq_mask.resize((tile_size, tile_size), Image.Resampling.LANCZOS)
    tile_mask = tile_mask.filter(ImageFilter.GaussianBlur(1.0))

    # Multi-stage Apple HIG drop shadows on transparent canvas
    amb_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    amb_offset_y = int(28 * ss)
    amb_shadow.paste((0, 0, 0, 48), (tile_margin, tile_margin + amb_offset_y), tile_mask)
    amb_shadow = amb_shadow.filter(ImageFilter.GaussianBlur(int(32 * ss)))
    master = Image.alpha_composite(master, amb_shadow)

    dir_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    dir_offset_y = int(14 * ss)
    dir_shadow.paste((0, 0, 0, 68), (tile_margin, tile_margin + dir_offset_y), tile_mask)
    dir_shadow = dir_shadow.filter(ImageFilter.GaussianBlur(int(14 * ss)))
    master = Image.alpha_composite(master, dir_shadow)

    # Rich Amber Gradient Surface: #FABB42 (top) to #AB6400 (bottom)
    top_r, top_g, top_b = 250, 187, 66
    bot_r, bot_g, bot_b = 171, 100, 0

    grad_col = Image.new("RGBA", (1, tile_size))
    for y in range(tile_size):
        ratio = y / float(tile_size)
        r = int(top_r + (bot_r - top_r) * ratio)
        g = int(top_g + (bot_g - top_g) * ratio)
        b = int(top_b + (bot_b - top_b) * ratio)
        grad_col.putpixel((0, y), (r, g, b, 255))
    tile_surf = grad_col.resize((tile_size, tile_size), Image.Resampling.NEAREST)

    tile_comp = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    tile_comp.paste(tile_surf, (tile_margin, tile_margin), tile_mask)
    master = Image.alpha_composite(master, tile_comp)

    # Inner Specular Highlight along top edge of tile
    top_hl = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    top_hl_mask = Image.new("L", (canvas_size, canvas_size), 0)
    top_hl_mask.paste(tile_mask, (tile_margin, tile_margin))
    top_hl_offset = Image.new("L", (canvas_size, canvas_size), 0)
    top_hl_offset.paste(tile_mask, (tile_margin, tile_margin + int(3.0 * ss)))

    diff_edge = ImageChops.subtract(top_hl_mask, top_hl_offset)
    diff_edge = diff_edge.filter(ImageFilter.GaussianBlur(int(1.0 * ss)))
    top_hl.paste((255, 255, 255, 140), (0, 0), diff_edge)
    master = Image.alpha_composite(master, top_hl)

    # Subtle Hairline Perimeter Contour
    border_im = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    border_mask = ImageChops.subtract(
        tile_mask.filter(ImageFilter.GaussianBlur(int(1.2 * ss))),
        tile_mask,
    )
    border_full = Image.new("L", (canvas_size, canvas_size), 0)
    border_full.paste(border_mask, (tile_margin, tile_margin))
    border_im.paste((0, 0, 0, 24), (0, 0), border_full)
    master = Image.alpha_composite(master, border_im)

    # Position Slanted 'H' Glyph in Center of Tile
    target_gh = int(tile_size * 0.54)
    target_gw = int(glyph_mask.width * (target_gh / glyph_mask.height))

    g_resized = glyph_mask.resize((target_gw, target_gh), Image.Resampling.LANCZOS)
    g_resized = g_resized.filter(ImageFilter.GaussianBlur(int(0.8 * ss)))

    gx = (canvas_size - target_gw) // 2
    gy = (canvas_size - target_gh) // 2

    # Multi-stage Warm Amber Drop Shadows under 3D Glyph onto Amber Tile
    # Broad soft ambient shadow
    g_shadow_wide = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    g_wide_mask = Image.new("L", (canvas_size, canvas_size), 0)
    g_wide_mask.paste(g_resized, (gx, gy + int(14 * ss)))
    g_shadow_wide.paste((55, 20, 0, 115), (0, 0), g_wide_mask)
    g_shadow_wide = g_shadow_wide.filter(ImageFilter.GaussianBlur(int(16 * ss)))
    master = Image.alpha_composite(master, g_shadow_wide)

    # Mid directional shadow
    g_shadow_mid = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    g_mid_mask = Image.new("L", (canvas_size, canvas_size), 0)
    g_mid_mask.paste(g_resized, (gx, gy + int(7 * ss)))
    g_shadow_mid.paste((50, 18, 0, 135), (0, 0), g_mid_mask)
    g_shadow_mid = g_shadow_mid.filter(ImageFilter.GaussianBlur(int(8 * ss)))
    master = Image.alpha_composite(master, g_shadow_mid)

    # Tight contact shadow
    g_shadow_key = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    g_key_mask = Image.new("L", (canvas_size, canvas_size), 0)
    g_key_mask.paste(g_resized, (gx, gy + int(3 * ss)))
    g_shadow_key.paste((40, 12, 0, 150), (0, 0), g_key_mask)
    g_shadow_key = g_shadow_key.filter(ImageFilter.GaussianBlur(int(3 * ss)))
    master = Image.alpha_composite(master, g_shadow_key)

    # Render 3D Tactile White Pill/Tube Slanted 'H' Glyph
    glyph_body = Image.new("RGBA", (target_gw, target_gh), (255, 255, 255, 255))

    # Shading: Light elevated from top-left (~315 degrees)
    underbelly_steps = [
        (-int(20 * ss), -int(4 * ss), int(16 * ss), 90, (170, 148, 132)),
        (-int(12 * ss), -int(2 * ss), int(10 * ss), 110, (185, 165, 150)),
        (-int(6 * ss), -int(1 * ss), int(5 * ss), 130, (198, 178, 164)),
        (-int(2.5 * ss), 0, int(2.5 * ss), 150, (180, 145, 130)),
    ]

    for dy, dx, blur_r, opacity, col in underbelly_steps:
        shifted = Image.new("L", (target_gw, target_gh), 0)
        shifted.paste(g_resized, (dx, dy))
        diff = ImageChops.subtract(g_resized, shifted)
        diff = diff.filter(ImageFilter.GaussianBlur(blur_r))
        layer = Image.new("RGBA", (target_gw, target_gh), (0, 0, 0, 0))
        layer.paste((*col, opacity), (0, 0), diff)
        glyph_body = Image.alpha_composite(glyph_body, layer)

    # Top Specular sheen & illumination
    top_steps = [
        (int(14 * ss), int(3 * ss), int(12 * ss), 180),
        (int(6 * ss), int(1 * ss), int(5 * ss), 255),
        (int(2.5 * ss), 0, int(2 * ss), 255),
    ]
    for dy, dx, blur_r, opacity in top_steps:
        shifted = Image.new("L", (target_gw, target_gh), 0)
        shifted.paste(g_resized, (dx, dy))
        diff = ImageChops.subtract(g_resized, shifted)
        diff = diff.filter(ImageFilter.GaussianBlur(blur_r))
        layer = Image.new("RGBA", (target_gw, target_gh), (0, 0, 0, 0))
        layer.paste((255, 255, 255, opacity), (0, 0), diff)
        glyph_body = Image.alpha_composite(glyph_body, layer)

    # Re-mask with g_resized for razor-sharp edges
    final_glyph = Image.new("RGBA", (target_gw, target_gh), (0, 0, 0, 0))
    final_glyph.paste(glyph_body, (0, 0), g_resized)

    # Composite 3D Glyph onto Master
    comp_glyph = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    comp_glyph.paste(final_glyph, (gx, gy))
    master = Image.alpha_composite(master, comp_glyph)

    app_icon_1024 = master.resize((1024, 1024), Image.Resampling.LANCZOS)
    app_icon_path = os.path.join(resources_dir, "AppIcon.png")
    app_icon_1024.save(app_icon_path)
    print(f"✅ Created {app_icon_path} (1024x1024)")

    # =========================================================================
    # 4. Multi-resolution Apple .icns bundle
    # =========================================================================
    iconset_dir = "/tmp/Shots_AppIcon.iconset"
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
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
    shutil.rmtree(iconset_dir, ignore_errors=True)
    print(f"✅ Created {icns_path}")

    # =========================================================================
    # 5. Crisp Status Bar Icons (Template + Light/Dark Mode)
    # =========================================================================
    def render_sb_assets(size, badge_size, ratio=0.58):
        margin = (size - badge_size) // 2
        t_resized = sq_mask.resize((badge_size, badge_size), Image.Resampling.LANCZOS)

        gh = int(round(badge_size * ratio))
        gw = int(round(glyph_mask.width * (gh / glyph_mask.height)))
        g_resized = glyph_mask.resize((gw, gh), Image.Resampling.LANCZOS)

        gx = (size - gw) // 2
        gy = (size - gh) // 2

        # 1. Native macOS Template Icon:
        # Solid squircle badge with slanted 'H' cutout hole.
        # Under macOS isTemplate=true:
        # - Light mode: badge tints black, cutout shows white menu bar -> black background, white letter
        # - Dark mode: badge tints white, cutout shows dark menu bar -> white background, black letter
        t_full = Image.new("L", (size, size), 0)
        t_full.paste(t_resized, (margin, margin))

        g_full = Image.new("L", (size, size), 0)
        g_full.paste(g_resized, (gx, gy))

        cutout_alpha = ImageChops.subtract(t_full, g_full)

        template_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        template_img.paste((0, 0, 0, 255), (0, 0), cutout_alpha)

        # 2. Explicit Light Mode: Black background, White letter
        light_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        light_img.paste((0, 0, 0, 255), (margin, margin), t_resized)
        light_img.paste((255, 255, 255, 255), (gx, gy), g_resized)

        # 3. Explicit Dark Mode: White background, Black letter
        dark_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        dark_img.paste((255, 255, 255, 255), (margin, margin), t_resized)
        dark_img.paste((0, 0, 0, 255), (gx, gy), g_resized)

        return template_img, light_img, dark_img

    sb_tmpl_18, sb_light_18, sb_dark_18 = render_sb_assets(18, 16, 0.58)
    sb_tmpl_36, sb_light_36, sb_dark_36 = render_sb_assets(36, 32, 0.58)

    # Save standard template icons
    sb_tmpl_18.save(os.path.join(resources_dir, "status-bar-icon.png"))
    sb_tmpl_18.save(os.path.join(resources_dir, "StatusBarIcon.png"))
    sb_tmpl_36.save(os.path.join(resources_dir, "status-bar-icon@2x.png"))
    sb_tmpl_36.save(os.path.join(resources_dir, "StatusBarIcon@2x.png"))

    # Save explicit light/dark mode assets
    sb_light_18.save(os.path.join(resources_dir, "StatusBarIcon_Light.png"))
    sb_light_36.save(os.path.join(resources_dir, "StatusBarIcon_Light@2x.png"))
    sb_dark_18.save(os.path.join(resources_dir, "StatusBarIcon_Dark.png"))
    sb_dark_36.save(os.path.join(resources_dir, "StatusBarIcon_Dark@2x.png"))

    print("✅ Created Status Bar icons: Template, Light (Black bg/White H), and Dark (White bg/Black H) (18x18 & 36x36)")

    # =========================================================================
    # 6. Clean Vector SVG Representation
    # =========================================================================
    svg_content = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <defs>
    <filter id="tileShadow" x="-10%" y="-10%" width="125%" height="135%">
      <feDropShadow dx="0" dy="3.5" stdDeviation="3.5" flood-color="#000000" flood-opacity="0.28"/>
    </filter>
    <filter id="glyphShadow" x="-15%" y="-15%" width="130%" height="140%">
      <feDropShadow dx="0" dy="2.2" stdDeviation="1.8" flood-color="#3B1700" flood-opacity="0.55"/>
    </filter>
    <linearGradient id="amberGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FABB42"/>
      <stop offset="100%" stop-color="#AB6400"/>
    </linearGradient>
  </defs>
  <!-- Outside Cushion Squircle Tile -->
  <path d="M 50,8 C 68,8 79,9 85,15 C 91,21 92,32 92,50 C 92,68 91,79 85,85 C 79,91 68,92 50,92 C 32,92 21,91 15,85 C 9,79 8,68 8,50 C 8,32 9,21 15,15 C 21,9 32,8 50,8 Z" fill="url(#amberGrad)" filter="url(#tileShadow)" stroke="rgba(0,0,0,0.08)" stroke-width="0.8"/>
  <path d="M 50,8.8 C 67.5,8.8 78.5,9.8 84.4,15.6 C 90.2,21.5 91.2,32.5 91.2,50 C 91.2,67.5 90.2,78.5 84.4,84.4 C 78.5,90.2 67.5,91.2 50,91.2 C 32.5,91.2 21.5,90.2 15.6,84.4 C 9.8,78.5 8.8,67.5 8.8,50 C 8.8,32.5 9.8,21.5 15.6,15.6 C 21.5,9.8 32.5,8.8 50,8.8 Z" fill="none" stroke="rgba(255,255,255,0.45)" stroke-width="0.8"/>
  <!-- 3D White Slanted 'H' Glyph -->
  <g filter="url(#glyphShadow)">
    <polygon points="36,28 44.5,28 35.5,72 27,72" fill="#FFFFFF"/>
    <polygon points="65,28 73.5,28 64.5,72 56,72" fill="#FFFFFF"/>
    <polygon points="39,47 68.5,47 67,54 37.5,54" fill="#FFFFFF"/>
  </g>
</svg>
"""
    svg_path = os.path.join(resources_dir, "AppIcon.svg")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg_content)
    print(f"✅ Created {svg_path}")

    # Clean up test artifacts
    for tmp_file in [
        "/tmp/test_exact_shape_appicon.png",
    ]:
        if os.path.exists(tmp_file):
            os.remove(tmp_file)

    print("🎉 All icons successfully generated with identical outside shape!")


if __name__ == "__main__":
    generate_icons()
