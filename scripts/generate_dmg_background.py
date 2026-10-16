#!/usr/bin/env python3
"""
Generates a minimal, ultra-clean retina-resolution custom DMG installer background
for Shots & Impact. Keeps only the top typography, the 3 glowing glass pedestals,
and two graceful rounded curved arrows guiding both apps into Applications.
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
    """Draws a soft radial glow onto the image composite."""
    glow_box = int(radius * 2.5)
    glow_surf = Image.new("RGBA", (glow_box, glow_box), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow_surf)
    gcx, gcy = glow_box // 2, glow_box // 2

    r_col, g_col, b_col, max_a = color
    steps = 22
    for step in range(steps, 0, -1):
        ratio = step / float(steps)
        rad = int(radius * ratio)
        alpha = int(max_a * ((1.0 - ratio) ** 1.6))
        if alpha > 0 and rad > 0:
            gdraw.ellipse(
                [gcx - rad, gcy - rad, gcx + rad, gcy + rad],
                fill=(r_col, g_col, b_col, alpha),
            )

    glow_surf = glow_surf.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(glow_surf, (cx - gcx, cy - gcy))


def draw_glass_pedestal(draw, cx, cy, radius, accent_color):
    """Draws a clean, modern frosted glass pedestal disc for an icon."""
    # Subtle drop shadow
    draw.ellipse(
        [cx - radius - 4, cy - radius, cx + radius + 4, cy + radius + 8],
        fill=(0, 0, 0, 50),
    )

    # Glass disc
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=(accent_color[0], accent_color[1], accent_color[2], 16),
        outline=(255, 255, 255, 45),
        width=2,
    )

    # Top rim reflection highlight
    draw.arc(
        [cx - radius + 2, cy - radius + 1, cx + radius - 2, cy + radius - 1],
        start=205,
        end=335,
        fill=(255, 255, 255, 95),
        width=2,
    )

    # Inner glowing accent ring
    in_r = radius - 14
    draw.ellipse(
        [cx - in_r, cy - in_r, cx + in_r, cy + in_r],
        outline=(accent_color[0], accent_color[1], accent_color[2], 80),
        width=1,
    )

    # Subtle corner tick marks
    tick_len = 10
    for angle in [45, 135, 225, 315]:
        rad = math.radians(angle)
        p1_x = cx + math.cos(rad) * (radius - 5)
        p1_y = cy + math.sin(rad) * (radius - 5)
        p2_x = cx + math.cos(rad) * (radius + tick_len)
        p2_y = cy + math.sin(rad) * (radius + tick_len)
        draw.line(
            [(p1_x, p1_y), (p2_x, p2_y)],
            fill=(accent_color[0], accent_color[1], accent_color[2], 120),
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

    # Draw glow underneath
    r, g, b = color[0], color[1], color[2]
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=(r, g, b, 45), width=width + 6)

    # Draw core crisp line
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

    # Filled sleek arrow head
    draw.polygon([(tip_x, tip_y), (left_x, left_y), (notch_x, notch_y), (right_x, right_y)], fill=color)


def generate_dmg_background():
    # 2x Retina resolution: 840 x 460 points = 1680 x 920 pixels
    W, H = 1680, 920
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    # 1. Base Gradient: Deep Space Obsidian to Slate Midnight
    for y in range(H):
        ny = y / float(H)
        r = int(12 + ny * 6)
        g = int(16 + ny * 8)
        b = int(28 + ny * 14)
        draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

    # 2. Key Anchor Coordinates (matching Finder coordinates 150, 370, 690 in 1x points)
    shots_x, shots_y = 300, 430
    impact_x, impact_y = 740, 430
    apps_x, apps_y = 1380, 430

    # Soft radial spotlights under the 3 pedestals
    draw_glow_circle(img, shots_x, shots_y, radius=220, color=(56, 189, 248, 60), blur=50)
    draw_glow_circle(img, impact_x, impact_y, radius=220, color=(244, 63, 94, 60), blur=50)
    draw_glow_circle(img, apps_x, apps_y, radius=240, color=(59, 130, 246, 75), blur=55)

    # Header glow
    draw_glow_circle(img, W // 2, 110, radius=340, color=(99, 102, 241, 35), blur=60)

    # 3. Vector Overlay Layer
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)

    # Pedestals
    ped_radius = 114
    draw_glass_pedestal(odraw, shots_x, shots_y, ped_radius, accent_color=(56, 189, 248))
    draw_glass_pedestal(odraw, impact_x, impact_y, ped_radius, accent_color=(244, 63, 94))
    draw_glass_pedestal(odraw, apps_x, apps_y, ped_radius, accent_color=(59, 130, 246))

    # 4. Two Rounded Sweeping Arrows into Applications
    # Arrow 1: High arching arrow from Shots (top-right) over to Applications (top-left)
    # Starts at top-right of Shots pedestal, arcs high, lands at Applications top-left
    arc_p0 = (shots_x + 85, shots_y - 75)
    arc_p1 = (580, 210)
    arc_p2 = (1100, 210)
    arc_p3 = (apps_x - 90, apps_y - 65)
    draw_curved_arrow(odraw, arc_p0, arc_p1, arc_p2, arc_p3, color=(244, 63, 94, 255), width=4, head_len=26, head_wing=18)

    # Arrow 2: Lower sweeping arrow from Impact (bottom-right) under to Applications (bottom-left)
    # Starts at bottom-right of Impact pedestal, swoops gently under, curves up into Applications
    swoop_p0 = (impact_x + 80, impact_y + 45)
    swoop_p1 = (960, 560)
    swoop_p2 = (1160, 560)
    swoop_p3 = (apps_x - 85, apps_y + 55)
    draw_curved_arrow(odraw, swoop_p0, swoop_p1, swoop_p2, swoop_p3, color=(244, 63, 94, 255), width=4, head_len=26, head_wing=18)

    # 5. Top Header Typography (The Callout Up Top)
    # Eyebrow tag
    eyebrow_text = "THE DYNAMIC SCREENSHOT & ANNOTATION DUO"
    eyebrow_font = get_font(16, weight="bold")
    ebbox = odraw.textbbox((0, 0), eyebrow_text, font=eyebrow_font)
    ew = ebbox[2] - ebbox[0]
    eh = ebbox[3] - ebbox[1]
    eb_pad_x = 20
    eb_pad_y = 8
    eb_x1 = W // 2 - ew // 2 - eb_pad_x
    eb_y1 = 46
    eb_x2 = W // 2 + ew // 2 + eb_pad_x
    eb_y2 = eb_y1 + eh + eb_pad_y * 2
    odraw.rounded_rectangle([eb_x1, eb_y1, eb_x2, eb_y2], radius=16, fill=(30, 41, 59, 180), outline=(148, 163, 184, 50), width=1)
    odraw.text((W // 2 - ew // 2, eb_y1 + eb_pad_y - 2), eyebrow_text, fill=(148, 163, 184, 230), font=eyebrow_font)

    # Main Headline
    main_title = "Take a Shot. Make an Impact."
    title_font = get_font(50, weight="bold")
    tbbox = odraw.textbbox((0, 0), main_title, font=title_font)
    tw = tbbox[2] - tbbox[0]
    odraw.text((W // 2 - tw // 2, 98), main_title, fill=(255, 255, 255, 255), font=title_font)

    # Subtitle
    subtitle_text = "Drag both apps into Applications to unlock your new screenshot superpowers"
    sub_font = get_font(21, weight="regular")
    sbbox = odraw.textbbox((0, 0), subtitle_text, font=sub_font)
    sw = sbbox[2] - sbbox[0]
    odraw.text((W // 2 - sw // 2, 166), subtitle_text, fill=(148, 163, 184, 220), font=sub_font)

    # Composite layers
    img = Image.alpha_composite(img, overlay)

    # Crisp window border
    final_draw = ImageDraw.Draw(img)
    final_draw.rectangle([0, 0, W - 1, H - 1], outline=(255, 255, 255, 28), width=1)

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
    generate_dmg_background()
