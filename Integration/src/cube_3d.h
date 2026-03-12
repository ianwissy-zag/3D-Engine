#ifndef CUBE_3D_H
#define CUBE_3D_H

#include <stdint.h>
#include <stdbool.h>
#include "player.h"

/* Fixed point configuration */
#define FIX_SHIFT 8
#define UNIT (1 << FIX_SHIFT)

/* Screen and camera configuration */
#define SCREEN_W 320
#define SCREEN_H 240
#define SCREEN_CX (SCREEN_W / 2)
#define SCREEN_CY (SCREEN_H / 2)

#define FOCAL_LEN (((160 * 65536) + (37837 / 2)) / 37837)
#define NEAR_CLIP (UNIT / 2 - UNIT / 8)

/* Mesh data structures */
typedef struct {
    int32_t x;
    int32_t y;
    int32_t z;
} vec3_t;

typedef struct {
    uint8_t i0, i1, i2, i3;
    uint8_t color;
} face_t;

typedef struct {
    uint8_t face_idx;
    int32_t depth;
} draw_face_t;

/* Rendering Interface */
void render_cube(CubeEntity* cube);

#endif // CUBE_3D_H