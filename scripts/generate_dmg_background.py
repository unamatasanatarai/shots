#!/usr/bin/env python3
"""
Generates a crisp, high-contrast light-themed retina-resolution custom DMG installer
background for Shots & Impact. Designed so that macOS Finder's black text labels are
100% sharp and legible. Features elegant frosted glass pedestals, clean top typography,
and two vibrant rounded curved arrows guiding both apps into Applications.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def get_font(size, weight="regular"):
    """Loads macOS system fonts with fallback support."""
    helvetica_path = "/System/Library/Fonts/HelveticaNeue.ttc"
    sf_path = "/System/Library/Fonts/SFNS.ttf"

    index_map = {
        "light": 7,
        "regular": 0,
        "bold": 1,
        "heavy": 9,
    }

    if os.path.exists(helvetica_path):
        idx = index_map.get(weight, 0)
        try:
            return ImageFont.truetype(helvetica_path, size, index=idx)
        except Exception:
            pass

    if os.path.exists(sf_path):
        try:
            return ImageFont.truetype(sf_path, size)
        except Exception:
            pass

    arial_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
    if os.path.exists(arial_path):
        try:
            return ImageFont.truetype(arial_path, size)
        except Exception:
            pass

    return ImageFont.load_default()


def draw_glow_circle(img, cx, cy, radius, color, blur=50):
    """Draws a soft diffused atmospheric aura onto the image composite."""
    glow_box = int(radius * 2.5)
    glow_surf = Image.new("RGBA", (glow_box, glow_box), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow_surf)
    gcx, gcy = glow_box // 2, glow_box // 2

    r_col, g_col, b_col, max_a = color
    steps = 20
    for step in range(steps, 0, -1):
        ratio = step / float(steps)
        rad = int(radius * ratio)
        alpha = int(max_a * ((1.0 - ratio) ** 1.5))
        if alpha > 0 and rad > 0:
            gdraw.ellipse(
                [gcx - rad, gcy - rad, gcx + rad, gcy + rad],
                fill=(r_col, g_col, b_col, alpha),
            )

    glow_surf = glow_surf.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(glow_surf, (cx - gcx, cy - gcy))


def draw_glass_pedestal(draw, cx, cy, radius, accent_color):
    """Draws a clean, modern white frosted glass pedestal disc for an icon."""
    # Soft drop shadow beneath pedestal
    draw.ellipse(
        [cx - radius - 4, cy - radius + 2, cx + radius + 4, cy + radius + 10],
        fill=(0, 0, 0, 22),
    )

    # Translucent white glass base disc
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=(255, 255, 255, 215),
        outline=(203, 213, 225, 230),
        width=2,
    )

    # Top rim highlight reflection
    draw.arc(
        [cx - radius + 2, cy - radius + 1, cx + radius - 2, cy + radius - 1],
        start=205,
        end=335,
        fill=(255, 255, 255, 255),
        width=2,
    )

    # Inner glowing accent ring
    in_r = radius - 14
    draw.ellipse(
        [cx - in_r, cy - in_r, cx + in_r, cy + in_r],
        outline=(accent_color[0], accent_color[1], accent_color[2], 120),
        width=1,
    )

    # 4 subtle corner tick marks
    tick_len = 10
    for angle in [45, 135, 225, 315]:
        rad = math.radians(angle)
        p1_x = cx + math.cos(rad) * (radius - 5)
        p1_y = cy + math.sin(rad) * (radius - 5)
        p2_x = cx + math.cos(rad) * (radius + tick_len)
        p2_y = cy + math.sin(rad) * (radius + tick_len)
        draw.line(
            [(p1_x, p1_y), (p2_x, p2_y)],
            fill=(accent_color[0], accent_color[1], accent_color[2], 170),
            width=2,
        )


def cubic_bezier_points(p0, p1, p2, p3, steps=60):
    """Computes points along a cubic bezier curve."""
    points = []
    for i in range(steps + 1):
        t = i / float(steps)
        x = (
            (1 - t) ** 3 * p0[0]
            + 3 * (1 - t) ** 2 * t * p1[0]
            + 3 * (1 - t) * t**2 * p2[0]
            + t**3 * p3[0]
        )
        y = (
            (1 - t) ** 3 * p0[1]
            + 3 * (1 - t) ** 2 * t * p1[1]
            + 3 * (1 - t) * t**2 * p2[1]
            + t**3 * p3[1]
        )
        points.append((x, y))
    return points


def draw_curved_arrow(draw, p0, p1, p2, p3, color, width=4, head_len=26, head_wing=18):
    """Draws a smooth cubic bezier arrow with a clean aerodynamic arrowhead."""
    points = cubic_bezier_points(p0, p1, p2, p3, steps=60)

    # Soft diffused shadow under the arrow
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=(color[0], color[1], color[2], 40), width=width + 6)

    # Crisp solid arrow body
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=color, width=width)

    # Compute tangent angle at arrival
    last_dx = points[-1][0] - points[-4][0]
    last_dy = points[-1][1] - points[-4][1]
    angle = math.atan2(last_dy, last_dx)

    tip_x, tip_y = points[-1]
    left_x = tip_x - head_len * math.cos(angle - 0.42)
    left_y = tip_y - head_len * math.sin(angle - 0.42)
    right_x = tip_x - head_len * math.cos(angle + 0.42)
    right_y = tip_y - head_len * math.sin(angle + 0.42)
    notch_x = tip_x - int(head_len * 0.7) * math.cos(angle)
    notch_y = tip_y - int(head_len * 0.7) * math.sin(angle)

    # Filled aerodynamic arrow head
    draw.polygon([(tip_x, tip_y), (left_x, left_y), (notch_x, notch_y), (right_x, right_y)], fill=color)


def generate_background():
    # 2x Retina resolution: 840 x 460 points = 1680 x 920 pixels
    W, H = 1680, 920
    img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)

    # 1. Base Gradient: Elegant Apple Silver-Platinum Light Theme
    for y in range(H):
        ny = y / float(H)
        r = int(248 - ny * 18)
        g = int(250 - ny * 15)
        b = int(252 - ny * 12)
        draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

    # 2. Key Anchor Coordinates (matching Finder coordinates in 1x points)
    shots_x, shots_y = 300, 434
    impact_x, impact_y = 740, 434
    apps_x, apps_y = 1380, 434

    # Soft pastel radial auras under each pedestal
    draw_glow_circle(img, shots_x, shots_y, radius=220, color=(186, 230, 253, 120), blur=50)
    draw_glow_circle(img, impact_x, impact_y, radius=220, color=(254, 205, 211, 120), blur=50)
    draw_glow_circle(img, apps_x, apps_y, radius=240, color=(191, 219, 254, 130), blur=55)

    # 3. Vector Overlay Layer
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)

    # Pedestals
    ped_radius = 114
    draw_glass_pedestal(odraw, shots_x, shots_y, ped_radius, accent_color=(2, 132, 199))
    draw_glass_pedestal(odraw, impact_x, impact_y, ped_radius, accent_color=(225, 29, 72))
    draw_glass_pedestal(odraw, apps_x, apps_y, ped_radius, accent_color=(37, 99, 235))

    # 4. Two Rounded Sweeping Red Arrows into Applications
    arrow_color = (239, 68, 68, 255)  # Vibrant Crimson Red

    # Arrow 1: High arching arrow from Shots (top-right) over to Applications (top-left)
    arc_p0 = (shots_x + 85, shots_y - 75)
    arc_p1 = (580, 210)
    arc_p2 = (1100, 210)
    arc_p3 = (apps_x - 90, apps_y - 65)
    draw_curved_arrow(odraw, arc_p0, arc_p1, arc_p2, arc_p3, color=arrow_color, width=4, head_len=26, head_wing=18)

    # Arrow 2: Lower sweeping arrow from Impact (bottom-right) under to Applications (bottom-left)
    swoop_p0 = (impact_x + 80, impact_y + 45)
    swoop_p1 = (960, 560)
    swoop_p2 = (1160, 560)
    swoop_p3 = (apps_x - 85, apps_y + 55)
    draw_curved_arrow(odraw, swoop_p0, swoop_p1, swoop_p2, swoop_p3, color=arrow_color, width=4, head_len=26, head_wing=18)

    # 5. Top Header Typography (Text on top removed as requested)
    # Main Headline (Deep Charcoal / Slate Black)
    main_title = "Take a Shot, Make an Impact"
    title_font = get_font(52, weight="bold")
    tbbox = odraw.textbbox((0, 0), main_title, font=title_font)
    tw = tbbox[2] - tbbox[0]
    odraw.text((W // 2 - tw // 2, 70), main_title, fill=(15, 23, 42, 255), font=title_font)

    # Subtitle (Refined Medium Slate)
    subtitle_text = "Drag both apps into Applications to unlock your new screenshot superpowers"
    sub_font = get_font(21, weight="regular")
    sbbox = odraw.textbbox((0, 0), subtitle_text, font=sub_font)
    sw = sbbox[2] - sbbox[0]
    odraw.text((W // 2 - sw // 2, 138), subtitle_text, fill=(71, 85, 105, 240), font=sub_font)

    # Composite layers
    img = Image.alpha_composite(img, overlay)

    # Crisp window border
    final_draw = ImageDraw.Draw(img)
    final_draw.rectangle([0, 0, W - 1, H - 1], outline=(203, 213, 225, 180), width=1)

    # Save 2x Retina master and downsampled 1x
    out_dir = "Resources"
    os.makedirs(out_dir, exist_ok=True)
    bg_2x_path = os.path.join(out_dir, "dmg_background@2x.png")
    bg_1x_path = os.path.join(out_dir, "dmg_background.png")

    img.save(bg_2x_path, "PNG")
    print(f"✅ Generated {bg_2x_path} ({W}x{H})")

    img_1x = img.resize((W // 2, H // 2), Image.Resampling.LANCZOS)
    img_1x.save(bg_1x_path, "PNG")
    print(f"✅ Generated {bg_1x_path} ({W // 2}x{H // 2})")


if __name__ == "__main__":
    generate_background()
