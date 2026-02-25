#include <stdint.h>

#include "config.h"
#include "player.h"
#include "raycaster.h"

/* Fixed-point math macros */
#ifndef TO_FP
#define TO_FP(x) ((x) << 16)
#endif
#ifndef FROM_FP
#define FROM_FP(x) ((x) >> 16)
#endif
#ifndef MUL_FP
#define MUL_FP(a, b) ((fixed32)(((int64_t)(a) * (b)) >> 16))
#endif

/* Pre-calculate constants to avoid float math during runtime */
#define PLAYER_SIZE_FP             PLAYER_SIZE * 65536
#define PLAYER_MOVEMENT_SPEED_FP   PLAYER_MOVEMENT_SPEED * 65536

/* Extern the LUTs from raycast.h */
extern const int32_t SIN_LUT[];
extern const int32_t COS_LUT[];

/* Internal fixed-point state */
fixed32 fpPlayerPosX;
fixed32 fpPlayerPosY;
uint8_t playerAngleIndex = 0; 

/* Toggles */
char movingForward    = FALSE;
char movingBack       = FALSE;
char turningLeft      = FALSE;
char turningRight     = FALSE;

#define ROT_SPEED_INT 2 

/* =========================================
 * FPGA / HARDWARE LOGIC (Pure Integer)
 * ========================================= */

void rotatePlayer(int direction) {
    playerAngleIndex += (direction * ROT_SPEED_INT);
}

int clipMovement(fixed32 dx, fixed32 dy) {
    fixed32 newx = fpPlayerPosX + dx;
    fixed32 newy = fpPlayerPosY + dy;
    
    int x1 = FROM_FP(newx - PLAYER_SIZE_FP) / WALL_SIZE;
    int y1 = FROM_FP(newy - PLAYER_SIZE_FP) / WALL_SIZE;
    int x2 = FROM_FP(newx + PLAYER_SIZE_FP) / WALL_SIZE;
    int y2 = FROM_FP(newy + PLAYER_SIZE_FP) / WALL_SIZE;
    
    int i, j;

    for(i = y1; i <= y2; i++) {
        for(j = x1; j <= x2; j++) {
            if(i < 0 || j < 0 || i >= MAP_GRID_HEIGHT || j >= MAP_GRID_WIDTH || MAP[i][j] > 0) {
                return TRUE;
            }
        }
    }

    return FALSE;
}

void movePlayer(fixed32 dx, fixed32 dy) {
    if(!clipMovement(dx, dy)) {
        fpPlayerPosX += dx;
        fpPlayerPosY += dy;
        return;
    }

    if(!clipMovement(0, dy)) {
        fpPlayerPosY += dy;
        return;
    }

    if(!clipMovement(dx, 0)) {
        fpPlayerPosX += dx;
        return;
    }
}

void updatePlayer() {
    fixed32 moveSpeed = PLAYER_MOVEMENT_SPEED_FP; 

    fixed32 dirX = COS_LUT[playerAngleIndex];
    fixed32 dirY = SIN_LUT[playerAngleIndex];

    if(movingForward) {
        movePlayer(MUL_FP(dirX, moveSpeed), MUL_FP(dirY, moveSpeed));
    } 
    if(movingBack) {
        movePlayer(MUL_FP(-dirX, moveSpeed), MUL_FP(-dirY, moveSpeed));
    } 
    
    int turnSpeed = 1;
    
    if(turningLeft) {
        rotatePlayer(-turnSpeed);
    } 
    if(turningRight) {
        rotatePlayer(turnSpeed);
    }
}


void initPlayer() {
    int row, col;

    for(row = 0; row < MAP_GRID_HEIGHT; row++) {
        for(col = 0; col < MAP_GRID_WIDTH; col++) {
            if(MAP[row][col] == P) {
                // Initialize internal fixed-point position
                fpPlayerPosX = TO_FP((WALL_SIZE * col) + (WALL_SIZE / 2));
                fpPlayerPosY = TO_FP((WALL_SIZE * row) + (WALL_SIZE / 2));
                return;
            }
        }
    }
}