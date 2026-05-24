from PIL import Image
from rembg import remove
import io

# Load the original logo
input_path = "assets/icon/logo_original.jpg"
output_path = "assets/icon/app_icon.png"
foreground_path = "assets/icon/app_icon_foreground.png"

# Read and remove background
with open(input_path, "rb") as f:
    input_data = f.read()

# Remove background
output_data = remove(input_data)

# Save as PNG with transparency
img = Image.open(io.BytesIO(output_data))
img = img.convert("RGBA")

# Create square icon (1024x1024)
size = max(img.size)
square_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
offset = ((size - img.width) // 2, (size - img.height) // 2)
square_img.paste(img, offset)

# Resize to 1024x1024
icon = square_img.resize((1024, 1024), Image.LANCZOS)
icon.save(output_path, "PNG")
print(f"Saved: {output_path}")

# Create foreground with padding for adaptive icon
foreground = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
# Scale down to 70% to fit within safe zone
scaled = icon.resize((716, 716), Image.LANCZOS)
foreground.paste(scaled, (154, 154), scaled)
foreground.save(foreground_path, "PNG")
print(f"Saved: {foreground_path}")

# Also create a version for splash screen
splash_icon = icon.resize((512, 512), Image.LANCZOS)
splash_icon.save("assets/icon/splash_logo.png", "PNG")
print("Saved: assets/icon/splash_logo.png")

print("Done! Now run: flutter pub run flutter_launcher_icons")
