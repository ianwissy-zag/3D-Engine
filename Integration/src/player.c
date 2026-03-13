#include <stdint.h>
#include <stdbool.h>
#include "config.h"
#include "player.h"
#include "raycaster.h"
#include "cube_3d.h"

/* --- Fixed-Point Math Macros --- */
// Fixed-point (FP) math allows us to do decimal calculations using fast integer operations.
// We use 16.16 format (16 bits for the whole number, 16 bits for the fraction).
#ifndef TO_FP
#define TO_FP(x) ((x) << 16)         // Convert standard integer to fixed-point
#endif
#ifndef FROM_FP
#define FROM_FP(x) ((x) >> 16)       // Convert fixed-point back to standard integer
#endif
#ifndef MUL_FP
// Multiply two FP numbers. We temporarily cast to int64_t to prevent overflow 
// during the multiplication, then shift back to maintain the 16.16 format.
#define MUL_FP(a, b) ((fixed32)(((int64_t)(a) * (b)) >> 16))
#endif

/* --- Constants --- */
#define PLAYER_SIZE_FP             (PLAYER_SIZE * 65536)         
#define PLAYER_MOVEMENT_SPEED_FP   (PLAYER_MOVEMENT_SPEED * 65536)
#define CUBE_SIZE_FP               (CUBE_SIZE * 65536)

// Lookup tables for trig functions, pre-calculated for 256 angles (0-255)
extern const int32_t SIN_LUT[];
extern const int32_t COS_LUT[];

/* --- Globals --- */
// The master array containing all cubes in the game world and their absolute states.
CubeEntity world_cubes[MAX_ACTIVE_CUBES];
int num_world_cubes = 0;

// Player position and rotation in fixed-point
fixed32 fpPlayerPosX;
fixed32 fpPlayerPosY;
fixed32 fpPlayerAngle;
uint8_t playerAngleIndex = 0; // 0-255 mapped angle for lookup tables

// Input state flags
char movingForward    = FALSE;
char movingBack       = FALSE;
char turningLeft      = FALSE;
char turningRight     = FALSE;

/* * Applies rotation to the player's angle based on input direction and delta time.
 * The angle wraps automatically when mapped back to the 8-bit playerAngleIndex.
 */
void rotatePlayer(int direction, fixed32 dt_mult) {
    fixed32 fp_rot_speed = TO_FP(ROT_SPEED_INT);
    fixed32 rot_amt = MUL_FP(fp_rot_speed, dt_mult) * direction;
    fpPlayerAngle += rot_amt;
    playerAngleIndex = (uint8_t)FROM_FP(fpPlayerAngle);
}

/* * Checks for collisions against the level grid using an Axis-Aligned Bounding Box (AABB).
 * Returns TRUE if the proposed movement overlaps a wall (MAP == 1).
 */
int clipMovement(fixed32 dx, fixed32 dy) {
    // Calculate proposed new position
    fixed32 newx = fpPlayerPosX + dx;
    fixed32 newy = fpPlayerPosY + dy;
    
    // Map the player's bounding box corners to the grid array indices
    int x1 = FROM_FP(newx - PLAYER_SIZE_FP) / WALL_SIZE;
    int y1 = FROM_FP(newy - PLAYER_SIZE_FP) / WALL_SIZE;
    int x2 = FROM_FP(newx + PLAYER_SIZE_FP) / WALL_SIZE;
    int y2 = FROM_FP(newy + PLAYER_SIZE_FP) / WALL_SIZE;
    
    // Check all grid cells the bounding box overlaps
    int i, j;
    for(i = y1; i <= y2; i++) {
        for(j = x1; j <= x2; j++) {
            // If out of bounds or hitting a wall block (1)
            if(i < 0 || j < 0 || i >= MAP_GRID_HEIGHT || j >= MAP_GRID_WIDTH || MAP[i][j] == 1) {
                return TRUE; // Collision detected
            }
        }
    }
    return FALSE; // Safe to move
}

/* * Moves the player and handles "sliding" against walls.
 * If moving diagonally into a wall, it tries moving only on the X axis, then only on the Y axis.
 */
void movePlayer(fixed32 dx, fixed32 dy) {
    // Try moving in both directions
    if(!clipMovement(dx, dy)) {
        fpPlayerPosX += dx;
        fpPlayerPosY += dy;
        return;
    }
    // If blocked, try sliding along the Y axis
    if(!clipMovement(0, dy)) {
        fpPlayerPosY += dy;
        return;
    }
    // If still blocked, try sliding along the X axis
    if(!clipMovement(dx, 0)) {
        fpPlayerPosX += dx;
        return;
    }
}

/* * Processes player input, calculates movement vectors, and applies delta time.
 */
void updatePlayer(fixed32 dt_mult) {
    fixed32 moveSpeed = MUL_FP(PLAYER_MOVEMENT_SPEED_FP, dt_mult); 

    // Get the normalized direction vector based on the player's current angle
    fixed32 dirX = COS_LUT[playerAngleIndex];
    fixed32 dirY = SIN_LUT[playerAngleIndex];

    // Apply movement
    if(movingForward) movePlayer(MUL_FP(dirX, moveSpeed), MUL_FP(dirY, moveSpeed));
    if(movingBack) movePlayer(MUL_FP(-dirX, moveSpeed), MUL_FP(-dirY, moveSpeed));
    
    // Apply rotation
    int turnSpeed = 1;
    if(turningLeft) rotatePlayer(-turnSpeed, dt_mult);
    if(turningRight) rotatePlayer(turnSpeed, dt_mult);
}

/* * Scans the map grid for the player start position ('P') and initializes coordinates.
 */
void initPlayer() {
    int row, col;
    for(row = 0; row < MAP_GRID_HEIGHT; row++) {
        for(col = 0; col < MAP_GRID_WIDTH; col++) {
            if(MAP[row][col] == P) { 
                // Center the player exactly in the middle of the grid tile
                fpPlayerPosX = TO_FP((WALL_SIZE * col) + (WALL_SIZE / 2));
                fpPlayerPosY = TO_FP((WALL_SIZE * row) + (WALL_SIZE / 2));
                fpPlayerAngle = TO_FP(playerAngleIndex);
                return;
            }
        }
    }
}


int check_cube_collision(fixed32 newx, fixed32 newy) {
    // Map the cube's bounding box corners to the grid array indices
    int x1 = FROM_FP(newx - CUBE_SIZE_FP) / WALL_SIZE;
    int y1 = FROM_FP(newy - CUBE_SIZE_FP) / WALL_SIZE;
    int x2 = FROM_FP(newx + CUBE_SIZE_FP) / WALL_SIZE;
    int y2 = FROM_FP(newy + CUBE_SIZE_FP) / WALL_SIZE;
    
    // Check all grid cells the bounding box overlaps
    for(int i = y1; i <= y2; i++) {
        for(int j = x1; j <= x2; j++) {
            // If out of bounds or hitting a wall block (1)
            if(i < 0 || j < 0 || i >= MAP_GRID_HEIGHT || j >= MAP_GRID_WIDTH || MAP[i][j] == 1) {
                return 1; // Collision detected
            }
        }
    }
    return 0; // Safe
}


/*
 * Updates the position and orientation of all active cubes in the world,
 * bouncing them off map walls.
 */
void update_cubes() {
    for (int i = 0; i < num_world_cubes; i++) {
        CubeEntity* cube = &world_cubes[i];
        
        if (cube->active) {
            // --- Update X Position ---
            if (check_cube_collision(cube->x + cube->dx, cube->y)) {
                // Hit a vertical wall, bounce X
                cube->dx = -cube->dx;
            } else {
                // Path is clear, move X
                cube->x += cube->dx;
            }

            // --- Update Y Position ---
            if (check_cube_collision(cube->x, cube->y + cube->dy)) {
                // Hit a horizontal wall, bounce Y
                cube->dy = -cube->dy;
            } else {
                // Path is clear, move Y
                cube->y += cube->dy;
            }

            // --- Update Orientation ---
            cube->yaw   += cube->dyaw;
            cube->pitch += cube->dpitch;
            cube->roll  += cube->droll;
        }
    }
}

/* * Scans the map grid for cube entities ('2') and spawns them into the world_cubes array.
 */
void init_entities() {
    num_world_cubes = 0; 
    for (int row = 0; row < MAP_GRID_HEIGHT; row++) {
        for (int col = 0; col < MAP_GRID_WIDTH; col++) {
            if (MAP[row][col] == 2) {
                if (num_world_cubes < MAX_ACTIVE_CUBES) {
                    CubeEntity* cube = &world_cubes[num_world_cubes];
                    
                    cube->active = true;
                    // Center the cube in the grid tile
                    cube->x = TO_FP((WALL_SIZE * col) + (WALL_SIZE / 2));
                    cube->y = TO_FP((WALL_SIZE * row) + (WALL_SIZE / 2));
                    // Set correct Z-height to sit flush on the floor
                    cube->z = TO_FP(UNIT/2); 
                    
                    // Reset orientation
                    cube->yaw = 0;
                    cube->pitch = 0;
                    cube->roll = 0;

                    // Reset rotation
                    cube->dyaw = 0;
                    cube->dpitch = 0;
                    cube->droll = 0;

                    // Reset movement
                    cube->dx = 0;
                    cube->dy = 0;
                    
                    num_world_cubes++;
                }
            }
        }
    }
}

/* * Transforms active cubes from world space into camera space, calculates their 
 * screen rendering size, handles item pickup logic, and builds the render list.
 */
int get_cubes_camera_offsets(CubeEntity** visible_cubes, int max_cubes) {
    int cube_count = 0;
    
    // Cache the camera's trig values for the rotation matrix
    fixed32 cos_a = COS_LUT[playerAngleIndex];
    fixed32 sin_a = SIN_LUT[playerAngleIndex];

    for (int i = 0; i < MAX_ACTIVE_CUBES; i++) {
        CubeEntity* currentCube = &world_cubes[i];
        
        if (!currentCube->active) continue; // Skip inactive/eaten cubes
        if (cube_count >= max_cubes) return cube_count; // Safety cap

        // Calculate vector from player to cube in absolute world space
        fixed32 dx = currentCube->x - fpPlayerPosX;
        fixed32 dy = currentCube->y - fpPlayerPosY;

        // Determine if the player is physically overlapping the cube (Pickup Logic)
        // We use absolute values to create a square bounding box around the player.
        fixed32 abs_dx = (dx < 0) ? -dx : dx;
        fixed32 abs_dy = (dy < 0) ? -dy : dy;
        
        if (abs_dx <= TO_FP(WALL_SIZE / 2 + 8) && abs_dy <= TO_FP(WALL_SIZE / 2 + 8)) {
            currentCube->active = 0; // "Eat" the cube
            continue; 
        }

        // Apply 2D rotation matrix to translate from World Space to Camera Space.
        // forward_dist is depth (Z in standard 3D, Y in our top-down 2D raycaster projection).
        fixed32 forward_dist = (fixed32)(((int64_t)dx * cos_a + (int64_t)dy * sin_a) >> 16);
        
        // Cull cubes that are behind the camera lens
        if (forward_dist <= 0) continue; 

        // right_dist is horizontal spread (X in camera space)
        fixed32 right_dist = (fixed32)(((int64_t)dx * (-sin_a) + (int64_t)dy * cos_a) >> 16);

        // Calculate distance for perspective projection
        fixed32 perpWallDist = forward_dist / WALL_SIZE; 
        if (perpWallDist <= 2048) perpWallDist = 2048; // Prevent division-by-zero or massive scaling

        // Calculate apparent size based on focal length / distance
        int32_t calc_height = (240 << 16) / perpWallDist;
        
        // Clamp height to prevent rendering overflow
        if (calc_height > 255) calc_height = 255;
        if (calc_height < 0) calc_height = 0;

        // Store the final calculated camera-space values in the entity for the renderer
        currentCube->height = TO_FP(calc_height);
        currentCube->offset_y = (int32_t)((forward_dist / WALL_SIZE) >> 8); 
        currentCube->offset_x = (int32_t)((right_dist / WALL_SIZE) >> 8);
        
        // Add valid cube to the rendering queue
        visible_cubes[cube_count] = currentCube;
        cube_count++;
    }
    
    return cube_count;
}

/* * Sorts the visible cubes using an Insertion Sort algorithm.
 * Cubes are sorted by their perceived screen 'height'. Because smaller height 
 * means the cube is further away, this effectively sorts them back-to-front.
 * This is required for the Painter's Algorithm so close cubes draw over far ones.
 */
void sort_cubes(CubeEntity** visible_cubes, int count) {
    for (int i = 1; i < count; i++) {
        CubeEntity* current_cube = visible_cubes[i];
        int j = i - 1;

        // Shift elements down if their height is greater (meaning they are closer)
        while (j >= 0 && visible_cubes[j]->height > current_cube->height) {
            visible_cubes[j + 1] = visible_cubes[j];
            j--;
        }
        
        // Insert the current cube into its sorted position
        visible_cubes[j + 1] = current_cube;
    }
}