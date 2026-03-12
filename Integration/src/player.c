#include <stdint.h>
#include <stdbool.h>
#include "config.h"
#include "player.h"
#include "raycaster.h"
#include "cube_3d.h"

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

#define PLAYER_SIZE_FP             (PLAYER_SIZE * 65536)         
#define PLAYER_MOVEMENT_SPEED_FP   (PLAYER_MOVEMENT_SPEED * 65536)

extern const int32_t SIN_LUT[];
extern const int32_t COS_LUT[];

/* Global arrays and state */
CubeEntity world_cubes[MAX_ACTIVE_CUBES];
int num_world_cubes = 0;

fixed32 fpPlayerPosX;
fixed32 fpPlayerPosY;
fixed32 fpPlayerAngle;
uint8_t playerAngleIndex = 0; 

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
            if(i < 0 || j < 0 || i >= MAP_GRID_HEIGHT || j >= MAP_GRID_WIDTH || MAP[i][j] == 1) {
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

    if(movingForward) movePlayer(MUL_FP(dirX, moveSpeed), MUL_FP(dirY, moveSpeed));
    if(movingBack) movePlayer(MUL_FP(-dirX, moveSpeed), MUL_FP(-dirY, moveSpeed));
    
    int turnSpeed = 1;
    if(turningLeft) rotatePlayer(-turnSpeed, dt_mult);
    if(turningRight) rotatePlayer(turnSpeed, dt_mult);
}

void initPlayer() {
    int row, col;
    for(row = 0; row < MAP_GRID_HEIGHT; row++) {
        for(col = 0; col < MAP_GRID_WIDTH; col++) {
            if(MAP[row][col] == P) { 
                fpPlayerPosX = TO_FP((WALL_SIZE * col) + (WALL_SIZE / 2));
                fpPlayerPosY = TO_FP((WALL_SIZE * row) + (WALL_SIZE / 2));
                fpPlayerAngle = TO_FP(playerAngleIndex);
                return;
            }
        }
    }
}

void init_entities() {
    num_world_cubes = 0; 
    for (int row = 0; row < MAP_GRID_HEIGHT; row++) {
        for (int col = 0; col < MAP_GRID_WIDTH; col++) {
            if (MAP[row][col] == 2) {
                if (num_world_cubes < MAX_ACTIVE_CUBES) {
                    CubeEntity* cube = &world_cubes[num_world_cubes];
                    
                    cube->active = true;
                    cube->x = TO_FP((WALL_SIZE * col) + (WALL_SIZE / 2));
                    cube->y = TO_FP((WALL_SIZE * row) + (WALL_SIZE / 2));
                    cube->z = TO_FP(UNIT/2); 
                    cube->yaw = 0;
                    cube->pitch = 0;
                    cube->roll = 0;
                    
                    num_world_cubes++;
                }
            }
        }
    }
}

int get_cubes_camera_offsets(CubeEntity** visible_cubes, int max_cubes) {
    int cube_count = 0;
    
    fixed32 cos_a = COS_LUT[playerAngleIndex];
    fixed32 sin_a = SIN_LUT[playerAngleIndex];

    for (int i = 0; i < MAX_ACTIVE_CUBES; i++) {
        CubeEntity* currentCube = &world_cubes[i];
        
        if (!currentCube->active) continue; 
        if (cube_count >= max_cubes) return cube_count; 

        fixed32 dx = currentCube->x - fpPlayerPosX;
        fixed32 dy = currentCube->y - fpPlayerPosY;

        fixed32 forward_dist = (fixed32)(((int64_t)dx * cos_a + (int64_t)dy * sin_a) >> 16);

        // Determine if the box is on top of (close to) the front of the player, and if it is 
        // eat it (remove it from the render list.)
        fixed32 abs_dx = (dx < 0) ? -dx : dx;
        fixed32 abs_dy = (dy < 0) ? -dy : dy;
        
        if (abs_dx <= TO_FP(WALL_SIZE / 2 + 8) && abs_dy <= TO_FP(WALL_SIZE / 2 + 8)) {
            currentCube->active = 0;
            continue; 
        }

        fixed32 right_dist = (fixed32)(((int64_t)dx * (-sin_a) + (int64_t)dy * cos_a) >> 16);

        fixed32 perpWallDist = forward_dist / WALL_SIZE; 
        if (perpWallDist <= 2048) perpWallDist = 2048; 

        int32_t calc_height = (240 << 16) / perpWallDist;
        if (calc_height > 255) calc_height = 255;
        if (calc_height < 0) calc_height = 0;

        currentCube->height = TO_FP(calc_height);
        currentCube->offset_y = (int32_t)((forward_dist / WALL_SIZE) >> 8); 
        currentCube->offset_x = (int32_t)((right_dist / WALL_SIZE) >> 8);
        
        visible_cubes[cube_count] = currentCube;
        cube_count++;
    }
    
    return cube_count;
}

void sort_cubes(CubeEntity** visible_cubes, int count) {
    for (int i = 1; i < count; i++) {
        CubeEntity* current_cube = visible_cubes[i];
        int j = i - 1;

        while (j >= 0 && visible_cubes[j]->height > current_cube->height) {
            visible_cubes[j + 1] = visible_cubes[j];
            j--;
        }
        
        visible_cubes[j + 1] = current_cube;
    }
}