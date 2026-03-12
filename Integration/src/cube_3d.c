#include <stdint.h>
#include <stdbool.h>
#include <vga_3d.h>
#include "cube_3d.h"
#include "player.h"

#define CAMERA_X 0
#define CAMERA_Y 0
#define CAMERA_Z (UNIT / 2)

#define CUBE_HALF (UNIT / 4)

static int32_t fx_mul(int32_t a, int32_t b) {
    return ((int64_t)(a * b)) >> FIX_SHIFT;
}

static int16_t sin_qtr[65] = {
    0, 6, 13, 19, 25, 31, 38, 44, 50, 56, 62, 68, 74,
    80, 86, 92, 98, 104, 109, 115, 121, 126, 132, 137, 142, 147,
    152, 157, 162, 167, 172, 177, 181, 185, 190, 194, 198, 202, 206,
    209, 213, 216, 220, 223, 226, 229, 231, 234, 237, 239, 241, 243, 
    245, 247, 248, 250, 251, 252, 253, 254, 255, 255, 256, 256, 256
};

static int16_t sin_u8(uint8_t angle) {
    uint8_t quadrant = angle >> 6; 
    uint8_t offset = angle & 0x3F; 

    switch (quadrant) {
        case 0: return sin_qtr[offset];
        case 1: return sin_qtr[64 - offset];
        case 2: return -sin_qtr[offset];
        default: return -sin_qtr[64 - offset];
    }
}

static int16_t cos_u8(uint8_t angle) {
    return sin_u8((uint8_t)(angle + 64));
}

static vec3_t rotate_x(vec3_t v, uint8_t angle) {
    int16_t s = sin_u8(angle);
    int16_t c = cos_u8(angle);

    vec3_t out;
    out.x = v.x;
    out.y = fx_mul(v.y, c) - fx_mul(v.z, s);
    out.z = fx_mul(v.y, s) + fx_mul(v.z, c);
    return out;
}

static vec3_t rotate_y(vec3_t v, uint8_t angle) {
    int16_t s = sin_u8(angle);
    int16_t c = cos_u8(angle);

    vec3_t out;
    out.x = fx_mul(v.x, c) + fx_mul(v.z, s);
    out.y = v.y;
    out.z = -fx_mul(v.x, s) + fx_mul(v.z, c);
    return out;
}

static vec3_t rotate_z(vec3_t v, uint8_t angle) {
    int16_t s = sin_u8(angle);
    int16_t c = cos_u8(angle);

    vec3_t out;
    out.x = fx_mul(v.x, c) - fx_mul(v.y, s);
    out.y = fx_mul(v.x, s) + fx_mul(v.y, c);
    out.z = v.z;
    return out;
}

static vec3_t cross3(vec3_t a, vec3_t b) {
    vec3_t out;
    out.x = a.y * b.z - a.z * b.y;
    out.y = a.z * b.x - a.x * b.z;
    out.z = a.x * b.y - a.y * b.x;
    return out;
}

static bool project_point(vec3_t v, point_t *out) {
    if (v.y <= NEAR_CLIP) {
        return false; 
    }

    int32_t sx = SCREEN_CX + (v.x * FOCAL_LEN) / v.y;
    int32_t sy = SCREEN_CY - (v.z * FOCAL_LEN) / v.y;

    out->x = (int16_t)sx; 
    out->y = (int16_t)sy;
    return true;
}

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

static face_t cube_faces[6] = {
    { 3, 7, 6, 2, 0xFF }, // front (+Y)
    { 0, 1, 5, 4, 0xF0 }, // back (-Y)
    { 1, 2, 6, 5, 0x0F }, // right (+X)
    { 0, 4, 7, 3, 0xF8 }, // left (-X)
    { 4, 5, 6, 7, 0x8F }, // top (+Z)
    { 0, 3, 2, 1, 0x88 }  // bottom (-Z)
};

static bool face_is_visible(vec3_t *v0, vec3_t *v1, vec3_t *v2) {
    vec3_t u = { v1->x - v0->x, v1->y - v0->y, v1->z - v0->z };
    vec3_t v = { v2->x - v0->x, v2->y - v0->y, v2->z - v0->z };
    vec3_t n = cross3(u, v);

    vec3_t center = {
        (v0->x + v1->x + v2->x) / 3,
        (v0->y + v1->y + v2->y) / 3,
        (v0->z + v1->z + v2->z) / 3
    };

    int64_t dot = (int64_t)n.x * center.x
                  + (int64_t)n.y * center.y 
                  + (int64_t)n.z * center.z;

    return (dot < 0);
}

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

void render_cube(CubeEntity* cube) {
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

       //  Apply rotations directly from the entity (Local Space)
        v = rotate_z(v, cube->yaw);
        v = rotate_x(v, cube->pitch);
        v = rotate_y(v, cube->roll);

        // Counter-rotate the vertices by the POSITIVE player angle 
        // to cancel out the camera rotation and lock the cube to the world grid.
        v = rotate_z(v, playerAngleIndex);

        // Apply camera-space offsets
        v.x += cube->offset_x;
        v.y += cube->offset_y;
        
        // Apply Z height
        v.z += (cube->z >> 16); 

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

        if (v0->y <= NEAR_CLIP || v1->y <= NEAR_CLIP ||
            v2->y <= NEAR_CLIP || v3->y <= NEAR_CLIP) {
            continue;
        }

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

    // Draw the visible faces
    for (uint8_t n = 0; n < draw_count; n++) {
        face_t *face = &cube_faces[draw_list[n].face_idx];

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
        
        draw_triangle(t0, face->color, cube->height >> 16);
        draw_triangle(t1, face->color, cube->height >> 16);
    }
}