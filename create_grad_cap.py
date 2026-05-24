from PIL import Image, ImageDraw
import math

def create_graduation_cap(size=512):
    # Create transparent image
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Colors
    cap_color = (26, 26, 46)  # Dark navy #1A1A2E
    gold_color = (139, 92, 246)  # Purple accent #8B5CF6
    tassel_color = (167, 139, 250)  # Light purple #A78BFA
    
    center_x = size // 2
    center_y = size // 2
    
    # Draw the mortarboard (square top)
    cap_size = int(size * 0.7)
    cap_top = center_y - int(size * 0.1)
    
    # Diamond shape for the top
    points = [
        (center_x, cap_top - int(cap_size * 0.3)),  # Top
        (center_x + int(cap_size * 0.5), cap_top),  # Right
        (center_x, cap_top + int(cap_size * 0.3)),  # Bottom
        (center_x - int(cap_size * 0.5), cap_top),  # Left
    ]
    draw.polygon(points, fill=cap_color)
    
    # Draw the skull cap (semi-circle bottom)
    skull_top = cap_top + int(cap_size * 0.15)
    skull_width = int(cap_size * 0.5)
    skull_height = int(cap_size * 0.35)
    
    # Draw skull cap as an ellipse arc
    skull_bbox = [
        center_x - skull_width,
        skull_top,
        center_x + skull_width,
        skull_top + skull_height * 2
    ]
    draw.chord(skull_bbox, 0, 180, fill=cap_color)
    
    # Draw button on top
    button_radius = int(size * 0.04)
    button_center = (center_x, cap_top)
    draw.ellipse([
        button_center[0] - button_radius,
        button_center[1] - button_radius,
        button_center[0] + button_radius,
        button_center[1] + button_radius
    ], fill=gold_color)
    
    # Draw tassel
    tassel_start = button_center
    tassel_end = (center_x + int(size * 0.25), cap_top + int(size * 0.35))
    
    # Tassel string
    draw.line([tassel_start, tassel_end], fill=tassel_color, width=int(size * 0.02))
    
    # Tassel end (rectangle with fringe effect)
    tassel_width = int(size * 0.06)
    tassel_height = int(size * 0.12)
    draw.rectangle([
        tassel_end[0] - tassel_width // 2,
        tassel_end[1],
        tassel_end[0] + tassel_width // 2,
        tassel_end[1] + tassel_height
    ], fill=tassel_color)
    
    return img

# Create different sizes
sizes = {
    'graduation_cap.png': 512,
    'graduation_cap_splash.png': 400,
}

for filename, size in sizes.items():
    img = create_graduation_cap(size)
    img.save(f'assets/icon/{filename}')
    print(f'Created {filename} ({size}x{size})')

print('Done!')
