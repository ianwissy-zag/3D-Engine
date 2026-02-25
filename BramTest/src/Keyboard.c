
// Delay
#define DELAY 0x00400000

// Switches and LED GPIO register addresses
#define VGA_CORDS    0x80001504
#define VGA_COLOR    0x80001508
#define VGA_CHAR     0x8000150C
#define KB_DATA      0x8000160C
#define KB_READY     0x80001610

const char scancode_to_ascii[] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '`', 0,      // 00-0F
    0, 0, 0, 0, 0, 'q', '1', 0, 0, 0, 'z', 's', 'a', 'w', '2', 0, // 10-1F
    0, 'c', 'x', 'd', 'e', '4', '3', 0, 0, ' ', 'v', 'f', 't', 'r', '5', 0, // 20-2F
    0, 'n', 'b', 'h', 'g', 'y', '6', 0, 0, 0, 'm', 'j', 'u', '7', '8', 0, // 30-3F
    0, ',', 'k', 'i', 'o', '0', '9', 0, 0, '.', '/', 'l', ';', 'p', '-', 0, // 40-4F
    0, 0, '\'', 0, '[', '=', 0, 0, 0, 0, '\n', ']', 0, '\\', 0, 0,        // 50-5F
    0, 0, 0, 0, 0, 0, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0      // 60-6F (0x66 is Backspace)
};

// This function reads the reg at address dir and returns the value.
inline int READ_REG(int dir){
    return (*(volatile unsigned *)dir);
}

// This function writes the value "value" to address "dir" and returns nothing.
inline void WRITE_REG(int dir, int value){
    (*(volatile unsigned *)dir) = (value);
    return;
}

int main ( void ){
    int old_char = 0;
    while(1){
        WRITE_REG(VGA_COLOR, 0x053);
        WRITE_REG(VGA_CORDS, 0xC030);
        int ready = READ_REG(KB_READY);
        if (ready == 1) {
            int current_char = READ_REG(KB_DATA);
            current_char = scancode_to_ascii[current_char];
            if (current_char != old_char & current_char != 0){
                WRITE_REG(VGA_CHAR, current_char);
            }
        }
    }
    // This should never be reached
    return 1;
}