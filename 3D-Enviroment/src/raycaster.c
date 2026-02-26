#include <stdio.h>
#include <stdint.h>

#include "config.h"
#include "raycaster.h"
#include "player.h"


#define GPU_ADR 0x80001500 

/* Expose the player's true integer state */
extern fixed32 fpPlayerPosX;
extern fixed32 fpPlayerPosY;
extern uint8_t playerAngleIndex;

// Camera x position lookup table [-1, 1] in fixed-point
fixed32 cameraX_LUT[VIEWPLANE_LENGTH];
char lut_initialized = 0;

// This function reads the reg at address dir and returns the value.
inline int READ_REG(int dir){
    return (*(volatile unsigned *)dir);
}

// This function writes the value "value" to address "dir" and returns nothing.
inline void WRITE_REG(int dir, int value){
    (*(volatile unsigned *)dir) = (value);
    return;
}

void run_integer_raycast() {
    // Load the lookup table for x positions 
    if (!lut_initialized) {
        for (int x = 0; x < VIEWPLANE_LENGTH; x++) {
            // Map x coordinate to range [-1, 1] in fixed-point
            cameraX_LUT[x] = IDIV(TO_FP(2 * x), TO_FP(VIEWPLANE_LENGTH)) - TO_FP(1);
        }
        lut_initialized = 1;
    }

    // 2. Convert world coords to map coords using bitwise shift instead of division
    fixed32 posX = fpPlayerPosX >> WALL_SHIFT;
    fixed32 posY = fpPlayerPosY >> WALL_SHIFT;
    
    fixed32 dirX = COS_LUT[playerAngleIndex];
    fixed32 dirY = SIN_LUT[playerAngleIndex];

    fixed32 planeX = IMUL(-dirY, FOV_TAN_CONST);
    fixed32 planeY = IMUL(dirX, FOV_TAN_CONST);

    // 3. The Raycasting Loop
    for (int x = 0; x < VIEWPLANE_LENGTH; x++) {
        fixed32 cameraX = cameraX_LUT[x]; // Fetch from LUT
        
        fixed32 rayDirX = dirX + IMUL(planeX, cameraX);
        fixed32 rayDirY = dirY + IMUL(planeY, cameraX);

        int mapX = (int)(posX >> FP_SHIFT);
        int mapY = (int)(posY >> FP_SHIFT);

        // Safe "infinity" to prevent integer overflow in DDA
        fixed32 MAX_DIST = 1 << 30; 
        
        fixed32 deltaDistX = (rayDirX == 0) ? MAX_DIST : IABS(IDIV(TO_FP(1), rayDirX));
        fixed32 deltaDistY = (rayDirY == 0) ? MAX_DIST : IABS(IDIV(TO_FP(1), rayDirY));

        fixed32 sideDistX, sideDistY;
        int stepX, stepY;
        int hit = 0, side = 0;

        if (rayDirX < 0) {
            stepX = -1;
            sideDistX = IMUL((posX - TO_FP(mapX)), deltaDistX);
        } else {
            stepX = 1;
            sideDistX = IMUL((TO_FP(mapX + 1) - posX), deltaDistX);
        }
        if (rayDirY < 0) {
            stepY = -1;
            sideDistY = IMUL((posY - TO_FP(mapY)), deltaDistY);
        } else {
            stepY = 1;
            sideDistY = IMUL((TO_FP(mapY + 1) - posY), deltaDistY);
        }

        // --- The DDA Loop ---
        while (hit == 0) {
            if (sideDistX < sideDistY) {
                sideDistX += deltaDistX;
                mapX += stepX;
                side = 0;
            } else {
                sideDistY += deltaDistY;
                mapY += stepY;
                side = 1;
            }
            // Bounds check
            if (mapX >= 0 && mapX < MAP_GRID_WIDTH && mapY >= 0 && mapY < MAP_GRID_HEIGHT) {
                if (MAP[mapY][mapX] > 0) hit = 1;
            } else { 
                hit = 1; 
            }
        }

        // --- Distance Calculation ---
        fixed32 perpWallDist;
        if (side == 0) {
            fixed32 diff = TO_FP(mapX) - posX + (stepX == 1 ? 0 : TO_FP(1));
            perpWallDist = IDIV(diff, rayDirX);
        } else {
            fixed32 diff = TO_FP(mapY) - posY + (stepY == 1 ? 0 : TO_FP(1));
            perpWallDist = IDIV(diff, rayDirY);
        }

        if (perpWallDist <= 0) perpWallDist = 1;

        // Write to the GPU
        
        int height = (240 << FP_SHIFT) / perpWallDist;
        
        // Clamp height to 8-bit max (More than we need)
        if (height > 255) height = 255;
        if (height < 0) height = 0;

        // 2. Determine 8-bit color based on wall orientation
        uint8_t color;
        if (side == 0) {
            // Hit an X-axis boundary (East/West wall)
            color = 0xE0; 
        } else {
            // Hit a Y-axis boundary (North/South wall)
            color = 0x03; 
        }

        // 3. Pack data according to Wishbone module mapping:
        // [24:17] height | [16:9] color | [8:0] pixel_column
        uint32_t wb_data = 0;
        wb_data |= (x & 0x1FF);               // 9 bits for column
        wb_data |= (color & 0xFF) << 9;       // 8 bits for color
        wb_data |= (height & 0xFF) << 17;     // 8 bits for height

        // 4. Write to GPU
        WRITE_REG(GPU_ADR, wb_data);
    }
}

void updateRaycaster() {
    run_integer_raycast();
}

/* =========================================
 * TRIG LOOKUP TABLES
 * ========================================= */
const int32_t SIN_LUT[LUT_STEPS] = {
          0,    1608,    3216,    4821,    6424,    8022,    9616,   11204,
      12785,   14359,   15924,   17479,   19024,   20557,   22078,   23586,
      25080,   26558,   28020,   29466,   30893,   32303,   33692,   35062,
      36410,   37736,   39040,   40320,   41576,   42806,   44011,   45190,
      46341,   47464,   48559,   49624,   50660,   51665,   52639,   53581,
      54491,   55368,   56212,   57022,   57798,   58538,   59244,   59914,
      60547,   61145,   61705,   62228,   62714,   63162,   63572,   63944,
      64277,   64571,   64827,   65043,   65220,   65358,   65457,   65516,
      65536,   65516,   65457,   65358,   65220,   65043,   64827,   64571,
      64277,   63944,   63572,   63162,   62714,   62228,   61705,   61145,
      60547,   59914,   59244,   58538,   57798,   57022,   56212,   55368,
      54491,   53581,   52639,   51665,   50660,   49624,   48559,   47464,
      46341,   45190,   44011,   42806,   41576,   40320,   39040,   37736,
      36410,   35062,   33692,   32303,   30893,   29466,   28020,   26558,
      25080,   23586,   22078,   20557,   19024,   17479,   15924,   14359,
      12785,   11204,    9616,    8022,    6424,    4821,    3216,    1608,
          0,   -1608,   -3216,   -4821,   -6424,   -8022,   -9616,  -11204,
     -12785,  -14359,  -15924,  -17479,  -19024,  -20557,  -22078,  -23586,
     -25080,  -26558,  -28020,  -29466,  -30893,  -32303,  -33692,  -35062,
     -36410,  -37736,  -39040,  -40320,  -41576,  -42806,  -44011,  -45190,
     -46341,  -47464,  -48559,  -49624,  -50660,  -51665,  -52639,  -53581,
     -54491,  -55368,  -56212,  -57022,  -57798,  -58538,  -59244,  -59914,
     -60547,  -61145,  -61705,  -62228,  -62714,  -63162,  -63572,  -63944,
     -64277,  -64571,  -64827,  -65043,  -65220,  -65358,  -65457,  -65516,
     -65536,  -65516,  -65457,  -65358,  -65220,  -65043,  -64827,  -64571,
     -64277,  -63944,  -63572,  -63162,  -62714,  -62228,  -61705,  -61145,
     -60547,  -59914,  -59244,  -58538,  -57798,  -57022,  -56212,  -55368,
     -54491,  -53581,  -52639,  -51665,  -50660,  -49624,  -48559,  -47464,
     -46341,  -45190,  -44011,  -42806,  -41576,  -40320,  -39040,  -37736,
     -36410,  -35062,  -33692,  -32303,  -30893,  -29466,  -28020,  -26558,
     -25080,  -23586,  -22078,  -20557,  -19024,  -17479,  -15924,  -14359,
     -12785,  -11204,   -9616,   -8022,   -6424,   -4821,   -3216,   -1608,
};

const int32_t COS_LUT[LUT_STEPS] = {
      65536,   65516,   65457,   65358,   65220,   65043,   64827,   64571,
      64277,   63944,   63572,   63162,   62714,   62228,   61705,   61145,
      60547,   59914,   59244,   58538,   57798,   57022,   56212,   55368,
      54491,   53581,   52639,   51665,   50660,   49624,   48559,   47464,
      46341,   45190,   44011,   42806,   41576,   40320,   39040,   37736,
      36410,   35062,   33692,   32303,   30893,   29466,   28020,   26558,
      25080,   23586,   22078,   20557,   19024,   17479,   15924,   14359,
      12785,   11204,    9616,    8022,    6424,    4821,    3216,    1608,
          0,   -1608,   -3216,   -4821,   -6424,   -8022,   -9616,  -11204,
     -12785,  -14359,  -15924,  -17479,  -19024,  -20557,  -22078,  -23586,
     -25080,  -26558,  -28020,  -29466,  -30893,  -32303,  -33692,  -35062,
     -36410,  -37736,  -39040,  -40320,  -41576,  -42806,  -44011,  -45190,
     -46341,  -47464,  -48559,  -49624,  -50660,  -51665,  -52639,  -53581,
     -54491,  -55368,  -56212,  -57022,  -57798,  -58538,  -59244,  -59914,
     -60547,  -61145,  -61705,  -62228,  -62714,  -63162,  -63572,  -63944,
     -64277,  -64571,  -64827,  -65043,  -65220,  -65358,  -65457,  -65516,
     -65536,  -65516,  -65457,  -65358,  -65220,  -65043,  -64827,  -64571,
     -64277,  -63944,  -63572,  -63162,  -62714,  -62228,  -61705,  -61145,
     -60547,  -59914,  -59244,  -58538,  -57798,  -57022,  -56212,  -55368,
     -54491,  -53581,  -52639,  -51665,  -50660,  -49624,  -48559,  -47464,
     -46341,  -45190,  -44011,  -42806,  -41576,  -40320,  -39040,  -37736,
     -36410,  -35062,  -33692,  -32303,  -30893,  -29466,  -28020,  -26558,
     -25080,  -23586,  -22078,  -20557,  -19024,  -17479,  -15924,  -14359,
     -12785,  -11204,   -9616,   -8022,   -6424,   -4821,   -3216,   -1608,
          0,    1608,    3216,    4821,    6424,    8022,    9616,   11204,
      12785,   14359,   15924,   17479,   19024,   20557,   22078,   23586,
      25080,   26558,   28020,   29466,   30893,   32303,   33692,   35062,
      36410,   37736,   39040,   40320,   41576,   42806,   44011,   45190,
      46341,   47464,   48559,   49624,   50660,   51665,   52639,   53581,
      54491,   55368,   56212,   57022,   57798,   58538,   59244,   59914,
      60547,   61145,   61705,   62228,   62714,   63162,   63572,   63944,
      64277,   64571,   64827,   65043,   65220,   65358,   65457,   65516,
};