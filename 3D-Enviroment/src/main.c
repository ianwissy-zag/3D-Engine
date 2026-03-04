#include "config.h"
#include "raycaster.h"
#include "player.h"
#include <stdint.h>

#define KB_DATA      0x80001600 // Read address for keyboard data
#define GPU_RD_ADR   0x80001500 // Read address to determine if the VGA is done with a frame
#define GPU_CFD_ADR  0x80001508 // Write address to indicate that program is done with a frame
#define MTIME_ADR    0x80001020 // Read address for the rvFPGA timer module (low 32)

inline int READ_REG(int dir){
    return (*(volatile unsigned *)dir);
}

inline void WRITE_REG(int dir, int value){
    (*(volatile unsigned *)dir) = (value);
    return;
}

static inline uint32_t get_time() {
    return READ_REG(MTIME_ADR);
}

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
    {R,R,R,R,R,0,R,R,R,R},
    {R,R,R,R,R,0,R,R,R,R},
    {R,R,0,R,0,0,0,0,R,R},
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
char gameIsRunning = TRUE;

void readInputs(){
    int wasd_data = READ_REG(KB_DATA);
    if ((wasd_data >> 3) & 0x1) {
        movingForward = TRUE;
    }
    else movingForward = FALSE;
    if ((wasd_data >> 2) & 0x1) {
        turningLeft = TRUE;
    }
    else turningLeft = FALSE;
    if ((wasd_data >> 1) & 0x1) {
        movingBack = TRUE;
    }
    else movingBack = FALSE;
    if (wasd_data & 0x1) {
        turningRight = TRUE;
    }
    else turningRight = FALSE;
        
    return;
}

void main() {
    initPlayer();
    uint32_t last_time = get_time();

    while(1) {
        uint32_t current_time = get_time();
        uint32_t delta_time = current_time - last_time;
        last_time = current_time;

        // Multiply by 161 and shift right by 9 to approximate (delta_time * 65536) / 208333
        // Avoids slow divison
        fixed32 dt_mult = (delta_time * 161) >> 9;

        // This write indicates that the program is currently writing a frame
        // and the frame buffers shouldn't be swapped
        WRITE_REG(GPU_CFD_ADR, 0);
        // Determine the current frame that the GPU is writing for a later check
        // to see if it is done
        int old_bram_inx = READ_REG(GPU_RD_ADR);

        // Get the keyboard inputs
        readInputs();

        // Move the player
        updatePlayer(dt_mult);

        // determine the wall positions and write them out to the GPU
        updateRaycaster();

        // Indicate to the GPU/VGA that the program is done writing and that
        // it can switch frames
        WRITE_REG(GPU_CFD_ADR, 1);

        // Wait for the GPU to finish writing its current frame and swap, so that
        // the program can begin on the next frame. 
        while(1){
            int bram_inx = READ_REG(GPU_RD_ADR);
            if (bram_inx != old_bram_inx){
                break;
            }
        }
    } 
}