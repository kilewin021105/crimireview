"""
Generate CrimiReview app icon with graduation cap - bigger version.
"""

from PIL import Image, ImageDraw
import os
import math

ICON_SIZE = 1024
FOREGROUND_SIZE = 1024

# Colors
PURPLE_BG = (108, 92, 231)  # #6C5CE7
NAVY = (255, 255, 255)  # White for visibility
PURPLE_ACCENT = (139, 92, 246)  # Purple accent #8B5CF6
LIGHT_PURPLE = (167, 139, 250)  # Light purple #A78BFA
WHITE = (255, 255, 255)
GOLD = (255, 193, 7)

def create_graduation_cap(size=512, with_background=True, bg_color=PURPLE_BG):
    """Create graduation cap icon."""
    if with_background:
        img = Image.new('RGBA', (size, size), bg_color + (255,))
    else:
        img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    draw = ImageDraw.Draw(img)
    
    center_x = size // 2
    center_y = size // 2
    
    # Scale factor - BIGGER cap
    scale = size / 512 * 1.1  # 10% bigger
    
    # Draw the mortarboard (diamond top) - BIGGER
    cap_width = int(220 * scale)
    cap_height = int(130 * scale)
    cap_top = center_y - int(60 * scale)
    
    # Diamond shape for the top
    points = [
        (center_x, cap_top - cap_height),  # Top
        (center_x + cap_width, cap_top),  # Right
        (center_x, cap_top + cap_height),  # Bottom
        (center_x - cap_width, cap_top),  # Left
    ]
    draw.polygon(points, fill=NAVY)
    
    # Draw the skull cap (semi-circle bottom)
    skull_top = cap_top + int(50 * scale)
    skull_width = int(180 * scale)
    skull_height = int(120 * scale)
    
    skull_bbox = [
        center_x - skull_width,
        skull_top,
        center_x + skull_width,
        skull_top + skull_height * 2
    ]
    draw.chord(skull_bbox, 0, 180, fill=NAVY)
    
    # Draw button on top - BIGGER
    button_radius = int(22 * scale)
    button_center = (center_x, cap_top)
    draw.ellipse([
        button_center[0] - button_radius,
        button_center[1] - button_radius,
        button_center[0] + button_radius,
        button_center[1] + button_radius
    ], fill=GOLD)
    
    # Draw tassel - BIGGER
    tassel_start = button_center
    tassel_end = (center_x + int(110 * scale), cap_top + int(150 * scale))
    
    # Tassel string
    draw.line([tassel_start, tassel_end], fill=GOLD, width=int(12 * scale))
    
    # Tassel end (rectangle)
    tassel_width = int(35 * scale)
    tassel_height = int(70 * scale)
    draw.rectangle([
        tassel_end[0] - tassel_width // 2,
        tassel_end[1],
        tassel_end[0] + tassel_width // 2,
        tassel_end[1] + tassel_height
    ], fill=GOLD)
    
    # Add some fringe lines
    fringe_y = tassel_end[1] + tassel_height
    for i in range(-2, 3):
        fx = tassel_end[0] + i * int(7 * scale)
        draw.line([fx, fringe_y, fx, fringe_y + int(15 * scale)], fill=GOLD, width=int(4 * scale))
    
    return img

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    icon_dir = os.path.join(script_dir, "assets", "icon")
    
    os.makedirs(icon_dir, exist_ok=True)
    
    print("Generating app icon (graduation cap, bigger)...")
    app_icon = create_graduation_cap(ICON_SIZE, with_background=True, bg_color=PURPLE_BG)
    app_icon_path = os.path.join(icon_dir, "app_icon.png")
    app_icon.save(app_icon_path, "PNG")
    print(f"  Saved: {app_icon_path}")
    
    print("Generating adaptive foreground (bigger)...")
    foreground = create_graduation_cap(FOREGROUND_SIZE, with_background=False)
    foreground_path = os.path.join(icon_dir, "app_icon_foreground.png")
    foreground.save(foreground_path, "PNG")
    print(f"  Saved: {foreground_path}")
    
    print("Generating graduation cap for screens...")
    grad_cap = create_graduation_cap(512, with_background=False)
    grad_cap_path = os.path.join(icon_dir, "graduation_cap.png")
    grad_cap.save(grad_cap_path, "PNG")
    print(f"  Saved: {grad_cap_path}")
    
    print("Generating splash logo...")
    splash = create_graduation_cap(512, with_background=False)
    splash_path = os.path.join(icon_dir, "splash_logo.png")
    splash.save(splash_path, "PNG")
    print(f"  Saved: {splash_path}")
    
    print("\nIcon generation complete!")
    print("\nTo apply the icons, run:")
    print("  flutter pub get")
    print("  dart run flutter_launcher_icons")

if __name__ == "__main__":
    main()
