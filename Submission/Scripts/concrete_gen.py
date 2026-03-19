import random

def generate_concrete_rgb444_mem():
    width = 128
    height = 128
    filename = "concrete_rgb444_128x128.mem"

    # Texture parameters (0-255 scale)
    top_brightness = 210
    bottom_brightness = 50
    noise_intensity = 35

    with open(filename, "w") as f:
        f.write(f"// {width}x{height} RGB444 (RRRRGGGGBBBB) Rough Concrete Texture\n")
        f.write(f"// Top Brightness: {top_brightness}, Bottom: {bottom_brightness}\n\n")

        for y in range(height):
            progress = y / (height - 1)
            base_intensity = top_brightness - (progress * (top_brightness - bottom_brightness))
            
            for x in range(width):
                # 1. Generate the base grayscale value (0-255)
                noise = random.randint(-noise_intensity, noise_intensity)
                gray_val = int(base_intensity + noise)
                gray_val = max(0, min(255, gray_val))
                
                # 2. Extract top bits for each color channel to maintain grayscale
                # All channels get the top 4 bits for a balanced 12-bit grayscale
                r = (gray_val >> 4) & 0x0F  
                g = (gray_val >> 4) & 0x0F  
                b = (gray_val >> 4) & 0x0F  
                
                # 3. Pack into a single 12-bit value: RRRR GGGG BBBB
                pixel_val = (r << 8) | (g << 4) | b
                
                # 4. Write out the hex value (3 hex characters for 12 bits)
                f.write(f"{pixel_val:03X} ")
            
            f.write("\n")

    print(f"Success! Generated {filename} in RGB444 format.")

if __name__ == "__main__":
    generate_concrete_rgb444_mem()