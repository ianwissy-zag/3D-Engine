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
fixed32 fpPlayerAngle;
uint8_t playerAngleIndex = 0; 

/* Toggles */
char movingForward    = FALSE;
char movingBack       = FALSE;
char turningLeft      = FALSE;
char turningRight     = FALSE;

void rotatePlayer(int direction, fixed32 dt_mult) {
    fixed32 fp_rot_speed = TO_FP(ROT_SPEED_INT);
    fixed32 rot_amt = MUL_FP(fp_rot_speed, dt_mult) * direction;
    fpPlayerAngle += rot_amt;
    
    playerAngleIndex = (uint8_t)FROM_FP(fpPlayerAngle);
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

void updatePlayer(fixed32 dt_mult) {
    fixed32 moveSpeed = MUL_FP(PLAYER_MOVEMENT_SPEED_FP, dt_mult); 

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
        rotatePlayer(-turnSpeed, dt_mult);
    } 
    if(turningRight) {
        rotatePlayer(turnSpeed, dt_mult);
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
                fpPlayerAngle = TO_FP(playerAngleIndex);
                return;
            }
        }
    }
}

void get_cube_camera_offsets(int32_t *offset_x, int32_t *offset_y, int32_t *height) {
    int row, col;
    fixed32 cubeX = 0;
    fixed32 cubeY = 0;
    char found = 0;

    for (row = 0; row < MAP_GRID_HEIGHT; row++) {
        for (col = 0; col < MAP_GRID_WIDTH; col++) {
            if (MAP[row][col] == 2) {
                cubeX = TO_FP((WALL_SIZE * col) + (WALL_SIZE / 2));
                cubeY = TO_FP((WALL_SIZE * row) + (WALL_SIZE / 2));
                found = 1;
                break;
            }
        }
        if (found) break;
    }

    fixed32 dx = cubeX - fpPlayerPosX;
    fixed32 dy = cubeY - fpPlayerPosY;

    fixed32 cos_a = COS_LUT[playerAngleIndex];
    fixed32 sin_a = SIN_LUT[playerAngleIndex];

    // Calculate rotated distances (in 16.16 map pixels)
    fixed32 forward_dist = (fixed32)(((int64_t)dx * cos_a + (int64_t)dy * sin_a) >> 16);
    fixed32 right_dist = (fixed32)(((int64_t)dx * (-sin_a) + (int64_t)dy * cos_a) >> 16);

    // Convert to 16.16 tiles (Your original, correct method!)
    fixed32 perpWallDist = forward_dist / WALL_SIZE; 
    
    // Safety check: Clamp distance if player walks completely inside the cube's origin
    if (perpWallDist <= 2048) perpWallDist = 2048; 

    // Calculate height matches raycaster exactly
    int calc_height = (240 << 16) / perpWallDist;

    // STRICT 8-BIT CLAMP: Prevents hardware wraparound
    if (calc_height > 255) calc_height = 255;
    if (calc_height < 0) calc_height = 0;
    *height = calc_height;

    // Output offsets for the 3D renderer
    *offset_y = (forward_dist / WALL_SIZE) >> 8;
    *offset_x = (right_dist / WALL_SIZE) >> 8;
}