import random

def generate_concrete_rgb332_mem():
    width = 128
    height = 128
    filename = "concrete_rgb332_128x128.mem"

    # Texture parameters (0-255 scale)
    top_brightness = 210
    bottom_brightness = 50
    noise_intensity = 35

    with open(filename, "w") as f:
        f.write(f"// {width}x{height} RGB332 (RRRGGGBB) Rough Concrete Texture\n")
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
                # Red gets the top 3 bits
                r = (gray_val >> 5) & 0x07  
                # Green gets the top 3 bits
                g = (gray_val >> 5) & 0x07  
                # Blue gets the top 2 bits (since human eyes are less sensitive to blue)
                b = (gray_val >> 6) & 0x03  
                
                # 3. Pack into a single 8-bit byte: RRR GGG BB
                # (If you actually meant a 7-bit RRR GG BB, you would use: (r << 4) | (g_2bit << 2) | b)
                pixel_val = (r << 5) | (g << 2) | b
                
                # 4. Write out the hex value
                f.write(f"{pixel_val:02X} ")
            
            f.write("\n")

    print(f"Success! Generated {filename} in RGB332 format.")

if __name__ == "__main__":
    generate_concrete_rgb332_mem()