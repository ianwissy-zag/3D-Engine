from PIL import Image, ImageDraw, ImageFont

WIDTH = 320
HEIGHT = 240
FILENAME = "image.mem"

# Create a pure black canvas
img = Image.new("RGB", (WIDTH, HEIGHT), "black")
draw = ImageDraw.Draw(img)

# Draw an 80x80 white square in the center
SQUARE_SIZE = 80
center_x = WIDTH // 2
center_y = HEIGHT // 2

start_x = center_x - (SQUARE_SIZE // 2)
end_x   = center_x + (SQUARE_SIZE // 2)
start_y = center_y - (SQUARE_SIZE // 2)
end_y   = center_y + (SQUARE_SIZE // 2)

draw.rectangle([start_x, start_y, end_x, end_y], fill="white")

# Load the default PIL font
font = ImageFont.load_default()

# The text we want to draw
lines = ["540", "IN", "3D"]

# Calculate text block height to center it vertically
line_spacing = 4
total_text_height = 0
for line in lines:
    bbox = draw.textbbox((0, 0), line, font=font)
    total_text_height += (bbox[3] - bbox[1])
total_text_height += line_spacing * (len(lines) - 1)

# Draw the text line by line
current_y = center_y - (total_text_height // 2)

for line in lines:
    bbox = draw.textbbox((0, 0), line, font=font)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    
    # "red" evaluates to RGB (255, 0, 0)
    draw.text((center_x - w // 2, current_y), line, fill="red", font=font)
    current_y += h + line_spacing

# Convert the RGB canvas into your 8-bit RRRGGGBB format
with open(FILENAME, 'w') as f:
    for y in range(HEIGHT):
        for x in range(WIDTH):
            r, g, b = img.getpixel((x, y))
            
            # Downsample 8-bit color channels to 3-bit, 3-bit, 2-bit
            r_3bit = (r >> 5) & 0x07
            g_3bit = (g >> 5) & 0x07
            b_2bit = (b >> 6) & 0x03
            
            # Pack it into a single byte: RRRGGGBB
            pixel_val = (r_3bit << 5) | (g_3bit << 2) | b_2bit
            
            f.write(f"{pixel_val:02X}\n")

print(f"Successfully generated {FILENAME} with red text.")