# generate_mem.py
# Generates a .mem file for two 320x240 frame buffers

WIDTH = 320
HEIGHT = 240
NUM_BUFFERS = 2
FILENAME = "image.mem"

# 8-bit color format: RRRGGGBB
COLOR_BLACK = "00"
COLOR_WHITE = "FF" 

# Square dimensions (64x64 pixels in the center)
SQUARE_SIZE = 64
center_x = WIDTH // 2
center_y = HEIGHT // 2

start_x = center_x - (SQUARE_SIZE // 2)
end_x   = center_x + (SQUARE_SIZE // 2)
start_y = center_y - (SQUARE_SIZE // 2)
end_y   = center_y + (SQUARE_SIZE // 2)

with open(FILENAME, 'w') as f:
    for b in range(NUM_BUFFERS):
        # Optional: Add a comment in the .mem file to see where the buffer starts
        # f.write(f"// Buffer {b}\n") 
        
        for y in range(HEIGHT):
            for x in range(WIDTH):
                # Check if the current pixel is inside our square
                if (start_x <= x < end_x) and (start_y <= y < end_y):
                    f.write(f"{COLOR_WHITE}\n")
                else:
                    f.write(f"{COLOR_BLACK}\n")

print(f"Successfully generated {FILENAME}")
print(f"Total pixels: {WIDTH * HEIGHT * NUM_BUFFERS} ({NUM_BUFFERS} buffers of {WIDTH * HEIGHT})")