"""
Generate CrimiReview app icon matching the AppLogo design.
Purple gradient with CR text, book icon, and gold verified badge.
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Icon sizes
ICON_SIZE = 1024
FOREGROUND_SIZE = 1024

# Colors matching the app
PURPLE_START = (108, 92, 231)  # #6C5CE7
PURPLE_END = (136, 84, 208)    # #8854D0
GOLD = (255, 193, 7)           # Gold for badge
WHITE = (255, 255, 255)

def create_gradient(size, start_color, end_color, direction='diagonal'):
    """Create a gradient image."""
    img = Image.new('RGBA', (size, size))
    
    for y in range(size):
        for x in range(size):
            if direction == 'diagonal':
                ratio = (x + y) / (2 * size)
            else:
                ratio = y / size
            
            r = int(start_color[0] + (end_color[0] - start_color[0]) * ratio)
            g = int(start_color[1] + (end_color[1] - start_color[1]) * ratio)
            b = int(start_color[2] + (end_color[2] - start_color[2]) * ratio)
            
            img.putpixel((x, y), (r, g, b, 255))
    
    return img

def draw_rounded_rect(draw, bbox, radius, fill):
    """Draw a rounded rectangle."""
    x1, y1, x2, y2 = bbox
    draw.rectangle([x1 + radius, y1, x2 - radius, y2], fill=fill)
    draw.rectangle([x1, y1 + radius, x2, y2 - radius], fill=fill)
    draw.ellipse([x1, y1, x1 + 2*radius, y1 + 2*radius], fill=fill)
    draw.ellipse([x2 - 2*radius, y1, x2, y1 + 2*radius], fill=fill)
    draw.ellipse([x1, y2 - 2*radius, x1 + 2*radius, y2], fill=fill)
    draw.ellipse([x2 - 2*radius, y2 - 2*radius, x2, y2], fill=fill)

def create_app_icon():
    """Create the main app icon."""
    size = ICON_SIZE
    
    # Create gradient background
    img = create_gradient(size, PURPLE_START, PURPLE_END)
    draw = ImageDraw.Draw(img)
    
    # Draw subtle book shapes in background (light purple)
    book_color = (255, 255, 255, 30)
    
    # Create separate image for transparency
    overlay = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    
    # Draw book shapes
    overlay_draw.rectangle([150, 700, 350, 950], fill=(255, 255, 255, 25))
    overlay_draw.rectangle([200, 650, 400, 900], fill=(255, 255, 255, 20))
    
    overlay_draw.rectangle([650, 100, 850, 350], fill=(255, 255, 255, 25))
    overlay_draw.rectangle([700, 50, 900, 300], fill=(255, 255, 255, 20))
    
    img = Image.alpha_composite(img, overlay)
    draw = ImageDraw.Draw(img)
    
    # Draw "CR" text
    try:
        # Try to use a bold font
        font = ImageFont.truetype("arial.ttf", 380)
    except:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 380)
        except:
            font = ImageFont.load_default()
    
    text = "CR"
    
    # Get text bounding box
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    # Center text (slightly up to make room for badge visual)
    x = (size - text_width) // 2
    y = (size - text_height) // 2 - 50
    
    # Draw text shadow
    draw.text((x + 8, y + 8), text, font=font, fill=(0, 0, 0, 50))
    
    # Draw main text
    draw.text((x, y), text, font=font, fill=WHITE)
    
    # Draw small book icon below CR
    book_x = size // 2 - 60
    book_y = y + text_height + 30
    
    # Book pages
    draw.rectangle([book_x, book_y, book_x + 120, book_y + 80], fill=(255, 255, 255, 180))
    draw.rectangle([book_x + 5, book_y + 5, book_x + 115, book_y + 15], fill=(200, 200, 200, 180))
    draw.rectangle([book_x + 5, book_y + 25, book_x + 115, book_y + 35], fill=(200, 200, 200, 180))
    draw.rectangle([book_x + 5, book_y + 45, book_x + 115, book_y + 55], fill=(200, 200, 200, 180))
    draw.rectangle([book_x + 5, book_y + 65, book_x + 80, book_y + 75], fill=(200, 200, 200, 180))
    
    # Draw gold verified badge (bottom right)
    badge_size = 180
    badge_x = size - badge_size - 80
    badge_y = size - badge_size - 80
    
    # Badge circle
    draw.ellipse([badge_x, badge_y, badge_x + badge_size, badge_y + badge_size], 
                 fill=GOLD, outline=(218, 165, 32))
    
    # Checkmark on badge
    check_x = badge_x + badge_size // 2
    check_y = badge_y + badge_size // 2
    
    # Draw checkmark
    draw.line([check_x - 35, check_y, check_x - 10, check_y + 30], fill=WHITE, width=18)
    draw.line([check_x - 10, check_y + 30, check_x + 40, check_y - 25], fill=WHITE, width=18)
    
    return img

def create_foreground_icon():
    """Create adaptive icon foreground (just the content, no background)."""
    size = FOREGROUND_SIZE
    
    # Transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Adaptive icons need safe zone (center 66%)
    safe_margin = size * 0.17
    safe_size = size * 0.66
    
    # Draw "CR" text in white
    try:
        font = ImageFont.truetype("arial.ttf", 280)
    except:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 280)
        except:
            font = ImageFont.load_default()
    
    text = "CR"
    
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    x = (size - text_width) // 2
    y = (size - text_height) // 2 - 30
    
    # White text
    draw.text((x, y), text, font=font, fill=WHITE)
    
    # Book icon below
    book_x = size // 2 - 50
    book_y = y + text_height + 20
    
    draw.rectangle([book_x, book_y, book_x + 100, book_y + 65], fill=WHITE)
    draw.rectangle([book_x + 5, book_y + 5, book_x + 95, book_y + 12], fill=(200, 180, 230))
    draw.rectangle([book_x + 5, book_y + 18, book_x + 95, book_y + 25], fill=(200, 180, 230))
    draw.rectangle([book_x + 5, book_y + 31, book_x + 95, book_y + 38], fill=(200, 180, 230))
    draw.rectangle([book_x + 5, book_y + 44, book_x + 70, book_y + 51], fill=(200, 180, 230))
    
    # Gold badge
    badge_size = 140
    badge_x = size - badge_size - 200
    badge_y = size - badge_size - 200
    
    draw.ellipse([badge_x, badge_y, badge_x + badge_size, badge_y + badge_size], fill=GOLD)
    
    # Checkmark
    check_x = badge_x + badge_size // 2
    check_y = badge_y + badge_size // 2
    draw.line([check_x - 28, check_y, check_x - 8, check_y + 24], fill=WHITE, width=14)
    draw.line([check_x - 8, check_y + 24, check_x + 32, check_y - 20], fill=WHITE, width=14)
    
    return img

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    icon_dir = os.path.join(script_dir, "assets", "icon")
    
    os.makedirs(icon_dir, exist_ok=True)
    
    print("Generating app icon...")
    app_icon = create_app_icon()
    app_icon_path = os.path.join(icon_dir, "app_icon.png")
    app_icon.save(app_icon_path, "PNG")
    print(f"  Saved: {app_icon_path}")
    
    print("Generating adaptive foreground...")
    foreground = create_foreground_icon()
    foreground_path = os.path.join(icon_dir, "app_icon_foreground.png")
    foreground.save(foreground_path, "PNG")
    print(f"  Saved: {foreground_path}")
    
    print("\nIcon generation complete!")
    print("\nTo apply the icons, run:")
    print("  flutter pub get")
    print("  dart run flutter_launcher_icons")

if __name__ == "__main__":
    main()
