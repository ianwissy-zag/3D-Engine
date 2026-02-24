# generate_mem.py
# Generates a 320x240 .mem file for Verilog $readmemh

WIDTH = 320
HEIGHT = 240
FILENAME = "image.mem"

# 8-bit color format: RRRGGGBB
COLOR_BLACK = "00"
COLOR_WHITE = "FF" # 111_111_11 in binary

# Define our square (64x64 pixels in the center)
SQUARE_SIZE = 64
center_x = WIDTH // 2
center_y = HEIGHT // 2

start_x = center_x - (SQUARE_SIZE // 2)
end_x   = center_x + (SQUARE_SIZE // 2)
start_y = center_y - (SQUARE_SIZE // 2)
end_y   = center_y + (SQUARE_SIZE // 2)

with open(FILENAME, 'w') as f:
    for y in range(HEIGHT):
        for x in range(WIDTH):
            # Check if the current pixel is inside our square
            if (start_x <= x < end_x) and (start_y <= y < end_y):
                f.write(f"{COLOR_WHITE}\n")
            else:
                f.write(f"{COLOR_BLACK}\n")

print(f"Successfully generated {FILENAME} with {WIDTH * HEIGHT} pixels.")