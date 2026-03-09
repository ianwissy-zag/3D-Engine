#ifndef RENDER_3D_H
#define RENDER_3D_H

#include <stdint.h>
#include <stdbool.h>

/*
 * Fixed point configuration
 */
#define FIX_SHIFT 8
#define UNIT (1 << FIX_SHIFT)

/*
 * Screen and camera configuration
 */
#define SCREEN_W 320
#define SCREEN_H 240
#define SCREEN_CX (SCREEN_W / 2)
#define SCREEN_CY (SCREEN_H / 2)

#define FOCAL_LEN (((160 * 65536) + (37837 / 2)) / 37837)
#define NEAR_CLIP (UNIT / 4)

/*
 * Mesh data structures
 */
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

/*
 * Rendering Interface
 * * NOTE: Ensure you remove the `static` keyword from render_cube 
 * in your .c file so it can be linked externally!
 */
void render_cube(uint8_t yaw, uint8_t pitch, uint8_t roll, int32_t offset_x, int32_t offset_y, int32_t offset_z, uint32_t height);

#endif // RENDER_3D_H