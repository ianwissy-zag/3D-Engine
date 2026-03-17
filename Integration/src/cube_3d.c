#include <stdint.h>
#include <stdbool.h>
#include <vga_3d.h>
#include "cube_3d.h"
#include "player.h"

#define CAMERA_X 0
#define CAMERA_Y 0
#define CAMERA_Z (UNIT / 2)

#define CUBE_HALF (UNIT / 4)

#define SUN_DIR_X 192
#define SUN_DIR_Y 128
#define SUN_DIR_Z 256

#define AMBIENT_LIGHT 135
#define FULL_LIGHT 256

/*
 * Math Helpers
 */

/* Multiplies two fixed-point values and keeps the fixed-point scale */
static int32_t fx_mul(int32_t a, int32_t b) {
    return ((int64_t)(a * b)) >> FIX_SHIFT;
}

/* Returns the absolute value of a 32-bit integer */
static int32_t abs32(int32_t x) {
    return (x < 0) ? -x : x;
}

/*
 * Trig Helpers
 */

static int16_t sin_qtr[65] = {
    0, 6, 13, 19, 25, 31, 38, 44, 50, 56, 62, 68, 74,
    80, 86, 92, 98, 104, 109, 115, 121, 126, 132, 137, 142, 147,
    152, 157, 162, 167, 172, 177, 181, 185, 190, 194, 198, 202, 206,
    209, 213, 216, 220, 223, 226, 229, 231, 234, 237, 239, 241, 243, 
    245, 247, 248, 250, 251, 252, 253, 254, 255, 255, 256, 256, 256
};

/* Looks up a sine value from an 8-bit angle */
static int16_t sin_u8(uint8_t angle) {
    uint8_t quadrant = angle >> 6; 
    uint8_t offset = angle & 0x3F; 

    // Rebuild the full sine wave from one quarter table
    switch (quadrant) {
        case 0: return sin_qtr[offset];
        case 1: return sin_qtr[64 - offset];
        case 2: return -sin_qtr[offset];
        default: return -sin_qtr[64 - offset];
    }
}

/* Looks up a cosine value from an 8-bit angle */
static int16_t cos_u8(uint8_t angle) {
    return sin_u8((uint8_t)(angle + 64));
}

/*
 * Rotation Helpers
 */

/* Rotates a 3D vector around the X axis */
static vec3_t rotate_x(vec3_t v, uint8_t angle) {
    int16_t s = sin_u8(angle);
    int16_t c = cos_u8(angle);

    vec3_t out;
    out.x = v.x;
    out.y = fx_mul(v.y, c) - fx_mul(v.z, s);
    out.z = fx_mul(v.y, s) + fx_mul(v.z, c);
    return out;
}

/* Rotates a 3D vector around the Y axis */
static vec3_t rotate_y(vec3_t v, uint8_t angle) {
    int16_t s = sin_u8(angle);
    int16_t c = cos_u8(angle);

    vec3_t out;
    out.x = fx_mul(v.x, c) + fx_mul(v.z, s);
    out.y = v.y;
    out.z = -fx_mul(v.x, s) + fx_mul(v.z, c);
    return out;
}

/* Rotates a 3D vector around the Z axis */
static vec3_t rotate_z(vec3_t v, uint8_t angle) {
    int16_t s = sin_u8(angle);
    int16_t c = cos_u8(angle);

    vec3_t out;
    out.x = fx_mul(v.x, c) - fx_mul(v.y, s);
    out.y = fx_mul(v.x, s) + fx_mul(v.y, c);
    out.z = v.z;
    return out;
}

/*
 * Vector Helpers
 */

/* Computes the cross product of two 3D vectors */
static vec3_t cross3(vec3_t a, vec3_t b) {
    vec3_t out;
    out.x = a.y * b.z - a.z * b.y;
    out.y = a.z * b.x - a.x * b.z;
    out.z = a.x * b.y - a.y * b.x;
    return out;
}

/* Scales a vector so its largest component has magnitude 256 */
static vec3_t normalize_to_256(vec3_t v) {
    int32_t ax = abs32(v.x);
    int32_t ay = abs32(v.y);
    int32_t az = abs32(v.z);

    int32_t m = ax;
    if (ay > m) m = ay;
    if (az > m) m = az;

    if (m == 0) {
        vec3_t zero = {0, 0, 0};
        return zero;
    }

    vec3_t out;
    // Scale by the biggest axis to avoid square root
    out.x = (v.x * 256) / m;
    out.y = (v.y * 256) / m;
    out.z = (v.z * 256) / m;
    return out;
}

/*
 * Lighting
 */

/* Applies a brightness value to an RGB444 color */
static uint16_t shade_rgb444(uint16_t color, int32_t brightness) {
    if (brightness < 0) brightness = 0;
    if (brightness > 256) brightness = 256;

    uint32_t r = (color >> 8) & 0xF;
    uint32_t g = (color >> 4) & 0xF;
    uint32_t b = color & 0xF;

    r = (r * brightness) >> 8;
    g = (g * brightness) >> 8;
    b = (b * brightness) >> 8;

    if (r > 0xF) r = 0xF;
    if (g > 0xF) g = 0xF;
    if (b > 0xF) b = 0xF;

    return (uint16_t)((r << 8) | (g << 4) | b);
}

/* Calculates the lighting intensity for a face from its normal and sun direction */
static int32_t face_brightness(vec3_t *v0, vec3_t *v1, vec3_t *v2, vec3_t sun_dir) {
    vec3_t u = { v1->x - v0->x, v1->y - v0->y, v1->z - v0->z };
    vec3_t v = { v2->x - v0->x, v2->y - v0->y, v2->z - v0->z };
    vec3_t n = cross3(u, v);

    vec3_t nn = normalize_to_256(n);

    int32_t dot = nn.x * sun_dir.x + nn.y * sun_dir.y + nn.z * sun_dir.z;

    // Back-facing light gives no extra brightness
    if (dot < 0) dot = 0;

    int32_t lit = dot / 256;
    if (lit > 256) lit = 256;

    return AMBIENT_LIGHT + (((FULL_LIGHT - AMBIENT_LIGHT) * lit) >> 8);
}

/*
 * Projection
 */

/* Projects a camera-space 3D point onto the screen */
static bool project_point(vec3_t v, point_t *out) {
    if (v.y <= NEAR_CLIP) {
        return false; 
    }

    // Perspective divide using Y as depth
    int32_t sx = SCREEN_CX + (v.x * FOCAL_LEN) / v.y;
    int32_t sy = SCREEN_CY - (v.z * FOCAL_LEN) / v.y;

    out->x = (int16_t)sx; 
    out->y = (int16_t)sy;
    return true;
}

/*
 * Mesh Data
 */

static vec3_t cube_vertices[8] = {
    { -CUBE_HALF, -CUBE_HALF, -CUBE_HALF },
    { CUBE_HALF, -CUBE_HALF, -CUBE_HALF },
    { CUBE_HALF, CUBE_HALF, -CUBE_HALF },
    { -CUBE_HALF, CUBE_HALF, -CUBE_HALF },
    { -CUBE_HALF, -CUBE_HALF, CUBE_HALF },
    { CUBE_HALF, -CUBE_HALF, CUBE_HALF },
    { CUBE_HALF, CUBE_HALF, CUBE_HALF },
    { -CUBE_HALF, CUBE_HALF, CUBE_HALF }
};

static face_t foe_faces[6] = {
    { 3, 7, 6, 2, 0xF00 }, // front (+Y)
    { 0, 1, 5, 4, 0xF00 }, // back (-Y)
    { 1, 2, 6, 5, 0xF00 }, // right (+X)
    { 0, 4, 7, 3, 0xF00 }, // left (-X)
    { 4, 5, 6, 7, 0xF00 }, // top (+Z)
    { 0, 3, 2, 1, 0xF00 }  // bottom (-Z)
};

static face_t cube_faces[6] = {
    { 3, 7, 6, 2, 0x0F0 }, // front (+Y)
    { 0, 1, 5, 4, 0x0F0 }, // back (-Y)
    { 1, 2, 6, 5, 0x0F0 }, // right (+X)
    { 0, 4, 7, 3, 0x0F0 }, // left (-X)
    { 4, 5, 6, 7, 0x0F0 }, // top (+Z)
    { 0, 3, 2, 1, 0x0F0 }  // bottom (-Z)
};

/*
 * Faces
 */

/* Checks whether a face is pointing toward the camera */
static bool face_is_visible(vec3_t *v0, vec3_t *v1, vec3_t *v2) {
    vec3_t u = { v1->x - v0->x, v1->y - v0->y, v1->z - v0->z };
    vec3_t v = { v2->x - v0->x, v2->y - v0->y, v2->z - v0->z };
    vec3_t n = cross3(u, v);

    vec3_t center = {
        (v0->x + v1->x + v2->x) / 3,
        (v0->y + v1->y + v2->y) / 3,
        (v0->z + v1->z + v2->z) / 3
    };

    // Compare the face normal with its position from the camera
    int64_t dot = (int64_t)n.x * center.x
                  + (int64_t)n.y * center.y 
                  + (int64_t)n.z * center.z;

    return (dot < 0);
}

/* Sorts faces from farthest to nearest for painter-style drawing */
static void sort_faces_back_to_front(draw_face_t *list, uint8_t count) {
    for (uint8_t i = 0; i < count; i++) {
        for (uint8_t j = 0; j + 1 < count; j++) {
            if (list[j].depth < list[j + 1].depth) {
                draw_face_t tmp = list[j];
                list[j] = list[j + 1];
                list[j + 1] = tmp;
            }
        }
    }
}

/*
 * Rendering
 */

/* Transforms, culls, shades, and draws a cube entity */
void render_cube(CubeEntity* cube) {
    vec3_t world_space[8];
    vec3_t cam_space[8];
    point_t screen_pts[8];
    bool projected[8];

    int32_t safe_radius = CUBE_HALF * 2; 

    // Check if behind the camera
    if (cube->offset_y < -safe_radius) {
        return; 
    }

    // Check if in the frontal cone
    int32_t abs_x = (cube->offset_x < 0) ? -cube->offset_x : cube->offset_x;
    if ((cube->offset_y + safe_radius) * SCREEN_CX < abs_x * FOCAL_LEN) {
        return; 
    }

    // Transform all vertices: local -> rotated -> world -> camera-space
    for (uint8_t i = 0; i < 8; i++) {
        vec3_t v = cube_vertices[i];

        // Rotate the cube first in local space
        v = rotate_z(v, cube->yaw + playerAngleIndex); // Keep cube rotation in world space using player angle
        v = rotate_x(v, cube->pitch);
        v = rotate_y(v, cube->roll);

        // Move the cube into world space
        v.x += cube->offset_x;
        v.y += cube->offset_y;
        
        // Apply Z height
        v.z += (cube->z >> 16); 

        world_space[i] = v;

        // Shift from world space into camera space
        v.x -= CAMERA_X;
        v.y -= CAMERA_Y;
        v.z -= CAMERA_Z;

        cam_space[i] = v;
        projected[i] = project_point(v, &screen_pts[i]);
    }

    // Collect the visible faces
    draw_face_t draw_list[6];
    uint8_t draw_count = 0;

    for (uint8_t f = 0; f < 6; f++) {
        face_t *face = &cube_faces[f];

        vec3_t *v0 = &cam_space[face->i0];
        vec3_t *v1 = &cam_space[face->i1];
        vec3_t *v2 = &cam_space[face->i2];
        vec3_t *v3 = &cam_space[face->i3];

        // Skip faces that cross behind the near clip
        if (v0->y <= NEAR_CLIP || v1->y <= NEAR_CLIP ||
            v2->y <= NEAR_CLIP || v3->y <= NEAR_CLIP) {
            continue;
        }

        // Skip only if all four points failed projection
        if (!projected[face->i0] && !projected[face->i1] &&
            !projected[face->i2] && !projected[face->i3]) {
            continue;
        }

        if (!face_is_visible(v0, v1, v2)) {
            continue;
        }

        draw_list[draw_count].face_idx = f;
        draw_list[draw_count].depth =
        (v0->y + v1->y + v2->y + v3->y) >> 2; 
        draw_count++;
    }

    // Painter's Algorithm for the cube's internal faces
    sort_faces_back_to_front(draw_list, draw_count);

    vec3_t sun_world = { SUN_DIR_X, SUN_DIR_Y, SUN_DIR_Z };
    vec3_t sun_cam = rotate_z(sun_world, playerAngleIndex);

    for (uint8_t n = 0; n < draw_count; n++) {
        face_t *face;
        uint8_t face_index = draw_list[n].face_idx;
        if (cube->friend){
            face = &cube_faces[face_index];
        }
        else {
            face = &foe_faces[face_index];
        }

        vec3_t *v0 = &world_space[face->i0];
        vec3_t *v1 = &world_space[face->i1];
        vec3_t *v2 = &world_space[face->i2];

        int32_t brightness = face_brightness(v0, v1, v2, sun_cam);
        uint16_t lit_color = shade_rgb444(face->color, brightness);

        // Split the quad into two triangles for drawing
        triangle_t t0 = {
            screen_pts[face->i0],
            screen_pts[face->i1],
            screen_pts[face->i2]
        };

        triangle_t t1 = {
            screen_pts[face->i0],
            screen_pts[face->i2],
            screen_pts[face->i3]
        };
        
        // Send the triangles to the GPU using the chosen color
        draw_triangle(t0, lit_color, cube->height >> 16);
        draw_triangle(t1, lit_color, cube->height >> 16);
    }
}