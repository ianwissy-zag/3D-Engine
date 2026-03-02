import math

def generate_fixed_point_luts(steps=256, fp_shift=16):
    multiplier = 1 << fp_shift
    
    sin_values = []
    cos_values = []
    
    for i in range(steps):
        # Calculate angle in radians
        angle = (2 * math.pi * i) / steps
        
        # Calculate Sin and Cos, then convert to fixed point
        s_val = int(round(math.sin(angle) * multiplier))
        c_val = int(round(math.cos(angle) * multiplier))
        
        sin_values.append(s_val)
        cos_values.append(c_val)
    
    # Format for C code
    print(f"// Generated for {steps} steps using 16.{fp_shift} fixed-point")
    print(f"#define LUT_STEPS {steps}")
    print("\nconst int32_t SIN_LUT[LUT_STEPS] = {")
    print_list_formatted(sin_values)
    print("};\n")
    
    print("const int32_t COS_LUT[LUT_STEPS] = {")
    print_list_formatted(cos_values)
    print("};")

def print_list_formatted(data, cols=8):
    for i in range(0, len(data), cols):
        chunk = data[i:i+cols]
        line = ", ".join(f"{x:>7}" for x in chunk)
        print(f"    {line},")

if __name__ == "__main__":
    generate_fixed_point_luts(256)
