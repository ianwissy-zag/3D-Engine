#include "config.h"
#include "raycaster.h"
#include "player.h"
#include <stdint.h>

#define KB_DATA      0x80001600
#define GPU_RD_ADR   0x80001500
#define GPU_CFD_ADR  0x80001508 
#define MTIME_ADR    0x80001020 /* SweRVolf core timer (lower 32 bits) */

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
        fixed32 dt_mult = (delta_time * 161) >> 9;

        WRITE_REG(GPU_CFD_ADR, 0);
        int old_bram_inx = READ_REG(GPU_RD_ADR);

        readInputs();

        updatePlayer(dt_mult);

        updateRaycaster();

        WRITE_REG(GPU_CFD_ADR, 1);
        while(1){
            int bram_inx = READ_REG(GPU_RD_ADR);
            if (bram_inx != old_bram_inx){
                break;
            }
        }
    } 
}