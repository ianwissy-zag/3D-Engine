#include "config.h"
#include "raycaster.h"
#include "player.h"
#include "cube_3d.h"
#include "stdbool.h"
#include <vga_3d.h>
#include <stdint.h>

#define KB_DATA      0x80001600
#define GPU_RD_ADR   0x80001500
#define GPU_CFD_ADR  0x80001508 
#define MTIME_ADR    0x80001020 /* SweRVolf core timer (lower 32 bits) */

static inline uint32_t get_time() {
    return READ_REG(MTIME_ADR);
}

const short MAP[MAP_GRID_HEIGHT][MAP_GRID_WIDTH] = {
    {R,R,R,R,R,R,R,R,R,R},
    {R,R,0,R,0,0,P,0,R,R},
    {R,0,0,R,0,0,0,0,0,R},
    {R,0,0,R,R,R,R,0,0,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,0,0,0,0,0,0,0,2,R},
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

int main() {
    initPlayer();
    uint8_t yaw = 0;
    uint8_t pitch = 0;
    uint8_t roll = 0;

    set_control_reg(true, true);

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

        int32_t dyn_offset_x = 0;
        int32_t dyn_offset_y = 0;
        int32_t height = 0;

        get_cube_camera_offsets(&dyn_offset_x, &dyn_offset_y, &height);

        render_cube(yaw, pitch, roll, dyn_offset_x, dyn_offset_y, UNIT/4, (uint32_t)height);

        yaw += 1;
        pitch += 1;
        roll += 0;

        WRITE_REG(GPU_CFD_ADR, 1);
        while(1){
            int bram_inx = READ_REG(GPU_RD_ADR);
            if (bram_inx != old_bram_inx){
                break;
            }
        }
    } 
    return 0;
}