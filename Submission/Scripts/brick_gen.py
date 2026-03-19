import math

# Configuration
WIDTH, HEIGHT = 128, 128
FILENAME = "wall_texture_rgb444.mem"
BRICK_ROWS = 2
BRICK_COLS = 2
CORNER_RADIUS = 10

# Define base colors in standard 0-255 range to make noise math safer
MORTAR_RGB = (80, 80, 80)      # Dark Gray
BRICK_RGB = (180, 68, 34)      # Muted Red/Brown

def get_12bit_color(r, g, b):
    """Converts 0-255 RGB to 12-bit RRRRGGGGBBBB."""
    r_4bit = (r >> 4) & 0x0F
    g_4bit = (g >> 4) & 0x0F
    b_4bit = (b >> 4) & 0x0F
    return (r_4bit << 8) | (g_4bit << 4) | b_4bit

def generate_texture():
    pixels = [0] * (WIDTH * HEIGHT)
    
    for y in range(HEIGHT):
        # Shift every other row for a classic brick bond
        row_idx = y // (HEIGHT // BRICK_ROWS)
        x_offset = (WIDTH // 4) if (row_idx % 2 == 1) else 0
        
        for x in range(WIDTH):
            # Modular arithmetic handles the wrap-around for the offset rows
            real_x = (x + x_offset) % WIDTH
            
            # Local coordinates within a single brick cell
            cell_w, cell_h = WIDTH // BRICK_COLS, HEIGHT // BRICK_ROWS
            local_x = real_x % cell_w
            local_y = y % cell_h
            
            # Distance from the edges to create soft corners
            dist_x = min(local_x, cell_w - local_x)
            dist_y = min(local_y, cell_h - local_y)
            
            # Check if we are in the "mortar" or "soft corner" area
            is_mortar = False
            if dist_x < 4 or dist_y < 4:
                is_mortar = True
            elif dist_x < CORNER_RADIUS and dist_y < CORNER_RADIUS:
                # Circular corner logic
                if (CORNER_RADIUS - dist_x)**2 + (CORNER_RADIUS - dist_y)**2 > CORNER_RADIUS**2:
                    is_mortar = True

            if is_mortar:
                color = get_12bit_color(*MORTAR_RGB)
            else:
                # Add a little "grit" noise to the brick face
                # Scaled up slightly to be visible in 12-bit color chunks
                noise = (int(math.sin(x * 0.5) * 15) + int(math.cos(y * 0.5) * 15))
                noise = max(0, noise)
                
                # Apply noise safely to each channel before packing to prevent channel-bleed
                r = max(0, min(255, BRICK_RGB[0] + noise))
                g = max(0, min(255, BRICK_RGB[1] + noise))
                b = max(0, min(255, BRICK_RGB[2] + noise))
                
                color = get_12bit_color(r, g, b)

            pixels[y * WIDTH + x] = color

    # Write to .mem file (Hexadecimal format)
    with open(FILENAME, "w") as f:
        for p in pixels:
            # Output as 3-character hex (e.g., 0FA, 444, B42)
            f.write(f"{p:03X}\n")

    print(f"Texture generated: {FILENAME}")

if __name__ == "__main__":
    generate_texture()