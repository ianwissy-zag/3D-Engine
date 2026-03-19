/**
 * @file raycaster.c
 * @brief Fixed-Point Raycasting Engine for Hardware GPU
 * * This file contains the core logic for a fixed-point, DDA-based
 * (Digital Differential Analyzer) raycaster. It calculates perspective-correct
 * wall distances, heights, and texture coordinates based on the player's
 * position and field of view. The final render data is packed into a 32-bit
 * integer and written to a memory-mapped GPU register.
 * * Dependencies:
 * - config.h: Contains fixed-point macros and map data.
 * - raycaster.h: Contains raycaster configuration and declarations.
 * - player.h: Contains player state definitions.
 * Written by Ian Wyse based on code by Nick Stones-Havas
 * github.com/drdanick/raycaster-sdl with assistance from 
 * Google Gemini.
 */

#include <stdio.h>
#include <stdint.h>
#include "config.h"
#include "raycaster.h"
#include "player.h"

#define GPU_ADR 0x80001504 /* Expose the player's true integer state */

extern fixed32 fpPlayerPosX;
extern fixed32 fpPlayerPosY;
extern uint8_t playerAngleIndex;

// Camera x position lookup table [-1, 1] in fixed-point
fixed32 cameraX_LUT[VIEWPLANE_LENGTH];
char lut_initialized = 0;

// This function reads the reg at address dir and returns the value.
inline int READ_REG(int dir) {
    return (*(volatile unsigned*)dir);
}

// This function writes the value "value" to address "dir" and returns nothing.
inline void WRITE_REG(int dir, int value) {
    (*(volatile unsigned*)dir) = (value);
    return;
}

/**
 * @brief Executes a single frame's raycasting pass and sends data to the GPU.
 * * This function projects rays outward from the player's position across the
 * horizontal field of view. It utilizes a 2D grid stepping algorithm (DDA)
 * to find the nearest wall intersections.
 * * Once a wall is hit, it calculates:
 * 1. The perpendicular distance to avoid the "fisheye" effect.
 * 2. The projected vertical line height for the screen.
 * 3. The precise horizontal texture coordinate (0-127) for the hit wall.
 * * The data (column index, texture X coordinate, and vertical height) is packed
 * into a single 32-bit word and sent directly to the Wishbone-mapped GPU register.
 * * @note Relies on external global variables: fpPlayerPosX, fpPlayerPosY, playerAngleIndex.
 * @return void
 */
void updateRaycaster() {
    // Safe infinity (Max value much larger than any actual distance).
    fixed32 MAX_DIST = 1 << 24;

    // Convert world coords to map coords
    fixed32 posX = fpPlayerPosX >> WALL_SHIFT;
    fixed32 posY = fpPlayerPosY >> WALL_SHIFT;

    fixed32 dirX = COS_LUT[playerAngleIndex];
    fixed32 dirY = SIN_LUT[playerAngleIndex];

    // Calculate the camera plane for the player 
    fixed32 planeX = IMUL(-dirY, FOV_TAN_CONST);
    fixed32 planeY = IMUL(dirX, FOV_TAN_CONST);

    // Starting ray: The leftmost edge of the screen
    fixed32 rayDirX = dirX - planeX;
    fixed32 rayDirY = dirY - planeY;

    // Calculation of the angle step for each pixel column 
    fixed32 stepCameraX = IDIV(TO_FP(2), TO_FP(VIEWPLANE_LENGTH));
    fixed32 stepDirX = IMUL(planeX, stepCameraX);
    fixed32 stepDirY = IMUL(planeY, stepCameraX);

    // The Raycasting Loop
    for (int x = 0; x < VIEWPLANE_LENGTH; x++) {
        // Find which grid cell the player is currently in.
        int mapX = (int)(posX >> FP_SHIFT);
        int mapY = (int)(posY >> FP_SHIFT);

        // Epsilon check: If a ray is almost parallel to an axis, that coordinate's distance can become arbitraily large
        // This detects this behavior and caps it and the predefined "infinity" (MAX_DIST).
        fixed32 deltaDistX = (IABS(rayDirX) <= 64) ? MAX_DIST : IABS(IDIV(TO_FP(1), rayDirX));
        fixed32 deltaDistY = (IABS(rayDirY) <= 64) ? MAX_DIST : IABS(IDIV(TO_FP(1), rayDirY));

        fixed32 sideDistX, sideDistY;
        int stepX, stepY;
        int side = 0; // 0 for X-axis (E/W), 1 for Y-axis (N/S).

        // Determine if we are looking Left/Right or Up/Down and calculate 
        // the distance the ray has to travel to hit a gridline
        if (rayDirX < 0) {
            stepX = -1;
            sideDistX = IMUL((posX - TO_FP(mapX)), deltaDistX);
        }
        else {
            stepX = 1;
            sideDistX = IMUL((TO_FP(mapX + 1) - posX), deltaDistX);
        }
        if (rayDirY < 0) {
            stepY = -1;
            sideDistY = IMUL((posY - TO_FP(mapY)), deltaDistY);
        }
        else {
            stepY = 1;
            sideDistY = IMUL((TO_FP(mapY + 1) - posY), deltaDistY);
        }

        // Jump from gridline to gridline until we hit a wall tile (1 or 3).
        while (1) {
            if (sideDistX < sideDistY) {
                sideDistX += deltaDistX;
                mapX += stepX;
                side = 0;
            }
            else {
                sideDistY += deltaDistY;
                mapY += stepY;
                side = 1;
            }
            if (MAP[mapY][mapX] == 1 || MAP[mapY][mapX] == 3) break;
        }

        // --- Distance Calculation ---
        // Use perpendicular distance to the camera plane rather than 
        // distance to the player to keep walls perfectly flat on screen.
        fixed32 perpWallDist;
        if (side == 0) {
            perpWallDist = sideDistX - deltaDistX;
        }
        else {
            perpWallDist = sideDistY - deltaDistY;
        }

        if (perpWallDist <= 0) perpWallDist = 1;

        // Write to the GPU
        int height = (240 << FP_SHIFT) / perpWallDist;

        // Clamp height to 10-bit max
        if (height > 1023) height = 1023;
        if (height < 0) height = 0;

        // Flip texture if we are looking at the "back" of the wall to keep orientation correct.
        fixed32 wallX = (side == 0) ? (posY + IMUL(perpWallDist, rayDirY)) : (posX + IMUL(perpWallDist, rayDirX));
        // Convert wallX to a 7-bit (0-127) texture index.
        uint8_t texX = (wallX >> (FP_SHIFT - 7)) & 0x7F;

        if ((side == 0 && rayDirX > 0) || (side == 1 && rayDirY < 0)) {
            texX = 127 - texX;
        }

        // Pack data according to Wishbone module mapping:
        // [26:17] height (10 bits) | [16:9] texX (8 bits) | [8:0] pixel_column (9 bits)
        uint32_t wb_data = (x & 0x1FF) | ((texX & 0xFF) << 9) | ((height & 0x3FF) << 17);

        // Write to GPU
        WRITE_REG(GPU_ADR, wb_data);

        // Align raycast angle to the next pixel column
        rayDirX += stepDirX;
        rayDirY += stepDirY;
    }
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