import math

# Configuration
WIDTH, HEIGHT = 128, 128
FILENAME = "wall_texture.mem"
BRICK_ROWS = 2
BRICK_COLS = 2
MORTAR_COLOR = 0x49  # Darker Gray (010 010 01)
BRICK_BASE_COLOR = 0xB4 # Muted Red/Brown (101 101 00)
CORNER_RADIUS = 10

def get_8bit_color(r, g, b):
    """Converts 0-255 RGB to 8-bit RRRGGGBB."""
    r_3bit = (r >> 5) & 0x07
    g_3bit = (g >> 5) & 0x07
    b_2bit = (b >> 6) & 0x03
    return (r_3bit << 5) | (g_3bit << 2) | b_2bit

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
                color = MORTAR_COLOR
            else:
                # Add a little "grit" noise to the brick face
                noise = (int(math.sin(x * 0.5) * 5) + int(math.cos(y * 0.5) * 5))
                color = BRICK_BASE_COLOR + (noise if noise > 0 else 0)

            pixels[y * WIDTH + x] = color

    # Write to .mem file (Hexadecimal format)
    with open(FILENAME, "w") as f:
        for p in pixels:
            f.write(f"{p:02x}\n")

    print(f"Texture generated: {FILENAME}")

if __name__ == "__main__":
    generate_texture()