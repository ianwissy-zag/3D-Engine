#include "config.h"
#include "raycaster.h"
#include "player.h"

#define KB_DATA      0x8000160C
#define KB_READY     0x80001610
#define KB_RELEASE   0x80001614

// This function reads the reg at address dir and returns the value.
inline int READ_REG(int dir){
    return (*(volatile unsigned *)dir);
}

// This function writes the value "value" to address "dir" and returns nothing.
inline void WRITE_REG(int dir, int value){
    (*(volatile unsigned *)dir) = (value);
    return;
}

const char scancode_to_ascii[] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '`', 0,      // 00-0F
    0, 0, 0, 0, 0, 'q', '1', 0, 0, 0, 'z', 's', 'a', 'w', '2', 0, // 10-1F
    0, 'c', 'x', 'd', 'e', '4', '3', 0, 0, ' ', 'v', 'f', 't', 'r', '5', 0, // 20-2F
    0, 'n', 'b', 'h', 'g', 'y', '6', 0, 0, 0, 'm', 'j', 'u', '7', '8', 0, // 30-3F
    0, ',', 'k', 'i', 'o', '0', '9', 0, 0, '.', '/', 'l', ';', 'p', '-', 0, // 40-4F
    0, 0, '\'', 0, '[', '=', 0, 0, 0, 0, '\n', ']', 0, '\\', 0, 0,        // 50-5F
    0, 0, 0, 0, 0, 0, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0      // 60-6F (0x66 is Backspace)
};


const short MAP[MAP_GRID_HEIGHT][MAP_GRID_WIDTH] = {
    {R,R,R,R,R,R,R,R,R,R},
    {R,R,0,R,0,0,P,0,R,R},
    {R,0,0,R,0,0,0,0,0,R},
    {R,0,0,R,R,R,R,0,0,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,0,0,R,0,0,R,R,R,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,R,0,0,0,0,0,0,R,R},
    {R,R,R,R,R,R,R,R,R,R}
};


/* Program toggles */
char gameIsRunning    = TRUE;

void readInputs(){
    int ready = READ_REG(KB_READY);
    int release = READ_REG(KB_RELEASE);
    if (ready == 1) {
        int current_char = READ_REG(KB_DATA);
        current_char = scancode_to_ascii[current_char];
        if (current_char == 'w'){
            movingForward = TRUE;
        }
        if (current_char == 'a'){
            turningLeft = TRUE;
        }
        if (current_char == 's'){
            movingBack = TRUE;
        }
        if (current_char == 'd'){
            turningRight = TRUE;
        }
        if (release == 1){
            if (current_char == 'w'){
                movingForward = FALSE;
            }
            if (current_char == 'a'){
                turningLeft = FALSE;
            }
            if (current_char == 's'){
                movingBack = FALSE;
            }
            if (current_char == 'd'){
                turningRight = FALSE;
            }
        }
    }
    return;
}

void main() {
    initPlayer();
    while(1) {

        // character presses
        readInputs();

        /* Update the player */
        updatePlayer();

        /* Update the raycaster */
        updateRaycaster();

    } 
}