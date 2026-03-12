#ifndef PLAYER_H
#define PLAYER_H

#include <stdint.h>
#include <stdbool.h>
#include "raycaster.h" /* Included for the fixed32 definition, if present */

#ifndef FIXED32_DEFINED
#define FIXED32_DEFINED
typedef int32_t fixed32;
#endif

#define MAX_ACTIVE_CUBES 16

/* Global toggles */
extern char movingForward;
extern char movingBack;
extern char turningLeft;
extern char turningRight;
extern char playerIsRunning;

extern uint8_t playerAngleIndex;

/* --- UNIFIED STRUCT --- */
typedef struct {
    bool active;        // TRUE if this slot is in use
    
    // Persistent World Data
    fixed32 x;          // World X position
    fixed32 y;          // World Y position
    fixed32 z;          // World Z position (height off the floor)
    uint8_t yaw;
    uint8_t pitch;
    uint8_t roll;

    // Transient Rendering Data (Calculated fresh every frame)
    fixed32 height;     // Screen height/scale
    int32_t offset_x;   // Camera-space X
    int32_t offset_y;   // Camera-space Y (Depth)
} CubeEntity;

/* Global Master Array of entities */
extern CubeEntity world_cubes[MAX_ACTIVE_CUBES];

/* Functions */
void initPlayer();
void rotatePlayer(int direction, fixed32 dt_mult);
void updatePlayer(fixed32 dt_mult);
void movePlayer(fixed32 dx, fixed32 dy);
int clipMovement(fixed32 dx, fixed32 dy);

void init_entities();
int get_cubes_camera_offsets(CubeEntity** visible_cubes, int max_cubes);
void sort_cubes(CubeEntity** visible_cubes, int count);

#endif /* PLAYER_H */