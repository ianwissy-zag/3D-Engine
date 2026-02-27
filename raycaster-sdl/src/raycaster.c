#include <stdio.h>
#include <stdint.h>

#include "config.h"
#include "raycaster.h"
#include "player.h"

/* Globals */
float distFromViewplane;
RayTuple rays[VIEWPLANE_LENGTH];

/* Fixed-Point Macros */
typedef int32_t fixed32;
#define FP_SHIFT 16
#define TO_FP(x) ((fixed32)((x) * (1 << FP_SHIFT)))
#define IMUL(a, b) ((fixed32)(((int64_t)(a) * (b)) >> FP_SHIFT))
#define IDIV(a, b) ((fixed32)(((int64_t)(a) << FP_SHIFT) / (b)))
#define IABS(x) ((x) < 0 ? -(x) : (x))

#define FOV_TAN_CONST 37837
#define LUT_STEPS 256

/* Expose the player's true integer state */
extern fixed32 fpPlayerPosX;
extern fixed32 fpPlayerPosY;
extern uint8_t playerAngleIndex;

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

/* =========================================
 * INTEGER RAYCASTING ALGORITHM
 * ========================================= */

// THis shift ammount is associated with a wall size of 64
#define WALL_SHIFT 6 

// Camera x position lookup table [-1, 1] in fixed-point
fixed32 cameraX_LUT[VIEWPLANE_LENGTH];
char lut_initialized = 0;

void run_integer_raycast_test() {
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

        // --- The DDA Loop (Perfectly Optimized) ---
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

        // -------------------------------------------------------------
        // SDL Renderer Spoof (REMOVE THIS WHEN PORTING TO RISC-V)
        // -------------------------------------------------------------
        float fPerpDist = (float)perpWallDist / (float)(1 << FP_SHIFT);
        float rDX = (float)rayDirX / (float)(1 << FP_SHIFT);
        float rDY = (float)rayDirY / (float)(1 << FP_SHIFT);

        rays[x].vRay.x = rDX * fPerpDist * WALL_SIZE;
        rays[x].vRay.y = rDY * fPerpDist * WALL_SIZE;
        rays[x].hRay = rays[x].vRay; 
        
        /* * FOR THE FPGA:
         * Instead of the spoof above, you will do something like this here:
         * int columnHeight = (WINDOW_HEIGHT * WALL_SIZE) / (perpWallDist >> FP_SHIFT);
         * write_to_bram_fifo(x, columnHeight, color);
         */
    }
}

void updateRaycaster() {
    run_integer_raycast_test();
}

/* =========================================
 * HELPER FUNCTIONS FOR RENDERER
 * ========================================= */
Vector3f getTileCoordinateForVerticalRay(Vector3f* ray) {
    Vector3f coord;
    int pX = fpPlayerPosX >> 16;
    int pY = fpPlayerPosY >> 16;
    coord.x = (int)(pX + ray->x + ((ray->x < 0) ? (-1 * RAY_EPS) : (RAY_EPS))) / WALL_SIZE;
    coord.y = (int)(pY + ray->y + ((ray->y < 0) ? (-1 * EPS) : (EPS))) / WALL_SIZE;
    return coord;
}

Vector3f getTileCoordinateForHorizontalRay(Vector3f* ray) {
    Vector3f coord;
    int pX = fpPlayerPosX >> 16;
    int pY = fpPlayerPosY >> 16;
    coord.x = (int)(pX + ray->x + ((ray->x < 0) ? (-1 * EPS) : EPS)) / WALL_SIZE;
    coord.y = (int)(pY + ray->y + ((ray->y < 0) ? (-1 * RAY_EPS) : (RAY_EPS))) / WALL_SIZE;
    return coord;
}

void initRaycaster() {
    /* Infer viewplane distance from a given field of view angle */
    distFromViewplane = (WINDOW_WIDTH / 2.0f) / (float)(tan(FOV / 2.0f));
}