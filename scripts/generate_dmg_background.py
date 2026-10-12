#!/usr/bin/env python3
"""
Generates a stunning, retina-resolution custom DMG installer background image
for AbbrEx featuring an atmospheric blurred logo watermark, sleek directional
installation arrows, and designated drop targets.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Vector coordinates from AppIcon.svg
cx_ref = 345.0
cy_ref = 332.0
w_ref = 668.0

norm_p1 = [
    ((339 - cx_ref) / w_ref, (94 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (226 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (347 - cy_ref) / w_ref),
    ((339 - cx_ref) / w_ref, (215 - cy_ref) / w_ref),
    ((131 - cx_ref) / w_ref, (423 - cy_ref) / w_ref),
    ((11 - cx_ref) / w_ref,  (423 - cy_ref) / w_ref),
]

norm_p2 = [
    ((679 - cx_ref) / w_ref, (241 - cy_ref) / w_ref),
    ((679 - cx_ref) / w_ref, (362 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (570 - cy_ref) / w_ref),
    ((339 - cx_ref) / w_ref, (438 - cy_ref) / w_ref),
    ((339 - cx_ref) / w_ref, (317 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (449 - cy_ref) / w_ref),
]

def draw_glyph(draw, cx, cy, width, fill_color, outline_color=None, outline_width=1):
    poly1 = [(cx + x * width, cy + y * width) for x, y in norm_p1]
    poly2 = [(cx + x * width, cy + y * width) for x, y in norm_p2]
    if fill_color:
        draw.polygon(poly1, fill=fill_color)
        draw.polygon(poly2, fill=fill_color)
    if outline_color:
        for i in range(len(poly1)):
            draw.line([poly1[i], poly1[(i+1)%len(poly1)]], fill=outline_color, width=outline_width)
        for i in range(len(poly2)):
            draw.line([poly2[i], poly2[(i+1)%len(poly2)]], fill=outline_color, width=outline_width)

def get_font(size, bold=False):
    # Try HelveticaNeue Bold if bold requested
    if bold and os.path.exists("/System/Library/Fonts/HelveticaNeue.ttc"):
        try:
            return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size, index=1)
        except Exception:
            pass
    font_paths = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf"
    ]
    for path in font_paths:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()

def draw_vector_arrow(draw, start_x, end_x, y, color=(56, 189, 248, 255), line_w=4, head_len=24):
    # Main stem
    draw.line([(start_x, y), (end_x, y)], fill=color, width=line_w)
    # Sleek arrow head
    wing_y = int(head_len * 0.75)
    pts = [
        (end_x - head_len, y - wing_y),
        (end_x, y),
        (end_x - head_len, y + wing_y)
    ]
    draw.line([pts[0], pts[1]], fill=color, width=line_w)
    draw.line([pts[1], pts[2]], fill=color, width=line_w)

def generate_background():
    # 2x Retina resolution: 660 x 420 points = 1320 x 840 pixels
    W, H = 1320, 840
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    # 1. Base Gradient: Deep Space Obsidian to Navy Slate
    for y in range(H):
        ny = y / float(H)
        r = int(10 + ny * 8)
        g = int(14 + ny * 12)
        b = int(24 + ny * 20)
        draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

    # Add soft radial atmospheric ambient glow
    ambient = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    amb_draw = ImageDraw.Draw(ambient)
    center_x, center_y = W // 2, int(H * 0.45)
    max_r = int(W * 0.55)
    for r in range(max_r, 0, -10):
        factor = 1.0 - (r / max_r)
        alpha = int(45 * (factor ** 1.8))
        amb_draw.ellipse(
            [center_x - r, center_y - int(r * 0.65), center_x + r, center_y + int(r * 0.65)],
            fill=(38, 70, 115, alpha)
        )
    ambient = ambient.filter(ImageFilter.GaussianBlur(50))
    img = Image.alpha_composite(img, ambient)

    # 2. Large Faded & Blurred AbbrEx Logo Watermark
    logo_cx = W // 2
    logo_cy = int(H * 0.46)
    logo_w = int(720)

    # Soft glowing bloom under logo
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    draw_glyph(glow_draw, logo_cx, logo_cy, logo_w, fill_color=(56, 189, 248, 55))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(45))
    img = Image.alpha_composite(img, glow_layer)

    # Soft ambient shadow
    shadow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    draw_glyph(shadow_draw, logo_cx, logo_cy + 12, logo_w, fill_color=(15, 23, 42, 110))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(25))
    img = Image.alpha_composite(img, shadow_layer)

    # Faded frosted translucent fill
    logo_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    logo_draw = ImageDraw.Draw(logo_layer)
    draw_glyph(logo_draw, logo_cx, logo_cy, logo_w, fill_color=(255, 255, 255, 14))
    # Delicate frosted wireframe outline
    draw_glyph(logo_draw, logo_cx, logo_cy, logo_w, fill_color=None, outline_color=(255, 255, 255, 40), outline_width=2)
    img = Image.alpha_composite(img, logo_layer)

    # 3. Designated Drop Zones for App & Applications Folder
    # Left: AbbrEx.app at (320, 410)
    # Right: Applications at (1000, 410)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)

    left_x, icon_y = 320, 410
    right_x = 1000

    def draw_drop_pedestal(cx, cy):
        # 3D-like illuminated glass pedestal base under the icon
        ped_rx, ped_ry = 135, 135
        # Soft pedestal glow
        odraw.ellipse([cx - ped_rx, cy - ped_ry, cx + ped_rx, cy + ped_ry], fill=(255, 255, 255, 5), outline=(255, 255, 255, 28), width=2)
        # Inner accent ring
        odraw.ellipse([cx - ped_rx + 8, cy - ped_ry + 8, cx + ped_rx - 8, cy + ped_ry - 8], fill=None, outline=(56, 189, 248, 20), width=1)
        # 4 subtle corner tick marks
        tick_len = 12
        for angle in [45, 135, 225, 315]:
            rad = math.radians(angle)
            p1_x = cx + math.cos(rad) * (ped_rx - 6)
            p1_y = cy + math.sin(rad) * (ped_ry - 6)
            p2_x = cx + math.cos(rad) * (ped_rx + 6)
            p2_y = cy + math.sin(rad) * (ped_ry + 6)
            odraw.line([(p1_x, p1_y), (p2_x, p2_y)], fill=(56, 189, 248, 90), width=2)

    draw_drop_pedestal(left_x, icon_y)
    draw_drop_pedestal(right_x, icon_y)

    # 4. Creative Flow & Transfer Arrows
    # Connecting path from left icon to right icon (between x=465 and x=855, y=410)
    track_start_x = 465
    track_end_x = 855

    # Glowing pulse beam
    beam_w = 4
    for offset in range(-6, 7):
        b_alpha = int(22 * (1.0 - abs(offset) / 7.0))
        odraw.line([(track_start_x, icon_y + offset), (track_end_x, icon_y + offset)], fill=(56, 189, 248, b_alpha), width=1)
    odraw.line([(track_start_x, icon_y), (track_end_x, icon_y)], fill=(125, 211, 252, 120), width=3)

    # Dynamic chevron trail
    for ch_x in [505, 545, 775, 815]:
        ratio = (ch_x - track_start_x) / float(track_end_x - track_start_x)
        alpha = int(70 + 150 * ratio)
        c_size = 13
        pts = [
            (ch_x - c_size, icon_y - c_size),
            (ch_x, icon_y),
            (ch_x - c_size, icon_y + c_size)
        ]
        odraw.line([pts[0], pts[1]], fill=(147, 197, 253, alpha), width=3)
        odraw.line([pts[1], pts[2]], fill=(147, 197, 253, alpha), width=3)

    # Lead prominent arrow head approaching Applications folder
    head_size = 22
    lead_pts = [
        (track_end_x - head_size, icon_y - head_size),
        (track_end_x, icon_y),
        (track_end_x - head_size, icon_y + head_size)
    ]
    odraw.line([lead_pts[0], lead_pts[1]], fill=(56, 189, 248, 255), width=4)
    odraw.line([lead_pts[1], lead_pts[2]], fill=(56, 189, 248, 255), width=4)

    # Frosted Glass "Drag to install" badge in the center
    pill_w = 260
    pill_h = 56
    pill_x1 = (W - pill_w) // 2
    pill_y1 = icon_y - pill_h // 2
    pill_x2 = pill_x1 + pill_w
    pill_y2 = pill_y1 + pill_h

    # Frosted pill base with deep shadow
    odraw.rounded_rectangle([pill_x1, pill_y1, pill_x2, pill_y2], radius=28, fill=(15, 23, 42, 220), outline=(255, 255, 255, 55), width=2)
    # Inner luminous rim
    odraw.rounded_rectangle([pill_x1 + 2, pill_y1 + 2, pill_x2 - 2, pill_y2 - 2], radius=26, fill=None, outline=(56, 189, 248, 65), width=1)

    # Badge text: "Drag to install" + cleanly rendered vector arrow
    font_badge = get_font(21, bold=True)
    badge_label = "Drag to install"
    bbox = odraw.textbbox((0, 0), badge_label, font=font_badge)
    label_w = bbox[2] - bbox[0]
    label_h = bbox[3] - bbox[1]

    # Draw label text slightly left of center to leave room for vector arrow
    arrow_w = 22
    spacing = 10
    total_content_w = label_w + spacing + arrow_w
    content_start_x = (W - total_content_w) // 2
    text_y = icon_y - label_h // 2 - 2

    odraw.text((content_start_x, text_y), badge_label, fill=(241, 245, 249, 245), font=font_badge)

    # Draw vector arrow inside pill badge
    badge_arrow_start_x = content_start_x + label_w + spacing
    badge_arrow_end_x = badge_arrow_start_x + arrow_w
    draw_vector_arrow(odraw, badge_arrow_start_x, badge_arrow_end_x, icon_y, color=(56, 189, 248, 255), line_w=3, head_len=10)

    # 5. Top Header Typography
    app_name = os.environ.get("APP_NAME", "SwiftApp")
    app_subtitle = os.environ.get("APP_SUBTITLE", "Native macOS Application")

    title_font = get_font(42, bold=True)
    title_text = app_name
    t_bbox = odraw.textbbox((0, 0), title_text, font=title_font)
    tw = t_bbox[2] - t_bbox[0]
    odraw.text((W // 2 - tw // 2, 65), title_text, fill=(255, 255, 255, 245), font=title_font)

    sub_font = get_font(20, bold=False)
    sub_text = app_subtitle
    s_bbox = odraw.textbbox((0, 0), sub_text, font=sub_font)
    sw = s_bbox[2] - s_bbox[0]
    odraw.text((W // 2 - sw // 2, 122), sub_text, fill=(148, 163, 184, 210), font=sub_font)

    # 6. Bottom Helper Instruction
    helper_font = get_font(18, bold=False)
    helper_text = f"Drag {app_name} into Applications to install"
    h_bbox = odraw.textbbox((0, 0), helper_text, font=helper_font)
    hw = h_bbox[2] - h_bbox[0]
    odraw.text((W // 2 - hw // 2, H - 75), helper_text, fill=(100, 116, 139, 220), font=helper_font)

    # Composite layers
    img = Image.alpha_composite(img, overlay)

    # Delicate outer window border (for crisp edge definition in Finder)
    final_draw = ImageDraw.Draw(img)
    final_draw.rectangle([0, 0, W - 1, H - 1], outline=(255, 255, 255, 25), width=1)

    # Save 2x Retina master and downsampled 1x
    out_dir = "Resources"
    os.makedirs(out_dir, exist_ok=True)
    bg_2x_path = os.path.join(out_dir, "dmg_background@2x.png")
    bg_1x_path = os.path.join(out_dir, "dmg_background.png")

    img.save(bg_2x_path, "PNG")
    print(f"✅ Generated {bg_2x_path} ({W}x{H})")

    img_1x = img.resize((W // 2, H // 2), Image.Resampling.LANCZOS)
    img_1x.save(bg_1x_path, "PNG")
    print(f"✅ Generated {bg_1x_path} ({W//2}x{H//2})")

if __name__ == "__main__":
    generate_background()
