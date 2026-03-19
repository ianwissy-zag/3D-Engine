/**
 * @file main.c
 * @brief Core Game Loop and System Integration.
 *
 * This file serves as the entry point for the SweRVolf-based 3D game. It
 * manages the master game loop, synchronizes movement with the hardware
 * timer (MTIME), handles keyboard input, and coordinates between the
 * 2D Raycaster (walls) and the 3D Cube Renderer (entities). It also
 * contains the high-level win/loss state logic.
 * Written by Ian Wyse with assitance from Google Gemini
 */

#include "config.h"
#include "raycaster.h"
#include "player.h"
#include "cube_3d.h"
#include "stdbool.h"
#include <vga_3d.h>
#include <stdint.h>

#define KB_DATA      0x80001600
#define GPU_RD_ADR   0x80001500
#define GPU_CFD_ADR  0x80001508
#define MTIME_ADR    0x80001020 /* SweRVolf core timer (lower 32 bits) */

 /**
  * @brief Reads the lower 32 bits of the hardware timer.
  * @return Current value of the MTIME register.
  */
static inline uint32_t get_time() {
    return READ_REG(MTIME_ADR);
}

/**
 * @brief The static game world map grid.
 * R = Red Wall, P = Player Start, 0 = Empty, 2 = Friend Cube, 4 = Foe Cube.
 */
const short MAP[MAP_GRID_HEIGHT][MAP_GRID_WIDTH] = {
    {R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R},
    {R,R,0,R,0,0,P,0,R,R,R,0,0,0,0,0,2,0,0,R},
    {R,0,0,R,0,0,0,0,0,R,R,0,0,0,0,0,0,0,0,R},
    {R,0,0,R,R,R,R,0,0,R,R,0,0,R,0,0,0,0,0,R},
    {R,2,2,2,0,0,0,0,0,0,0,0,R,0,0,0,4,0,0,R},
    {R,2,2,2,0,0,0,0,2,R,R,R,0,0,0,0,R,R,R,R},
    {R,0,0,R,0,0,R,R,R,R,R,0,0,0,R,R,0,2,0,R},
    {R,0,0,0,0,0,0,0,4,R,R,0,0,R,0,0,0,0,0,R},
    {R,R,0,4,0,0,0,0,R,R,R,0,0,0,R,0,0,0,0,R},
    {R,R,R,R,R,0,R,R,R,R,R,0,0,0,0,4,R,0,0,R},
    {R,R,0,R,R,0,R,R,R,R,R,2,0,0,0,0,0,0,0,R},
    {R,R,0,R,0,0,0,0,R,R,R,R,R,R,R,R,R,R,0,R},
    {R,0,0,R,0,0,0,0,0,R,R,0,0,0,0,0,0,0,0,R},
    {R,0,0,R,R,R,R,0,0,R,R,0,0,0,0,0,0,4,0,R},
    {R,0,0,0,0,0,0,0,0,R,R,R,R,R,0,0,0,R,0,R},
    {R,0,4,0,0,0,0,4,0,R,R,0,0,0,4,0,0,0,0,R},
    {R,0,0,R,R,3,R,R,R,R,R,0,0,0,0,0,R,R,R,R},
    {R,0,0,R,0,0,0,0,2,R,R,0,0,0,0,0,R,0,0,R},
    {R,R,0,R,0,0,0,2,R,R,R,0,0,2,0,0,0,2,0,R},
    {R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R,R}
};

// Queue for sorting and rendering cubes that are within the camera frustum.
CubeEntity* visibleList[MAX_ACTIVE_CUBES];
extern CubeEntity world_cubes[MAX_ACTIVE_CUBES];

/**
 * @brief Reads bit-mapped movement data from the keyboard register.
 * Decodes WASD or Arrow inputs into global boolean flags for the player controller.
 */
void readInputs() {
    int wasd_data = READ_REG(KB_DATA);
    movingForward = (wasd_data >> 3) & 0x1;
    turningLeft = (wasd_data >> 2) & 0x1;
    movingBack = (wasd_data >> 1) & 0x1;
    turningRight = wasd_data & 0x1;
}

/**
 * @brief Triggers the game-over animation.
 * Performs a slow screen wipe by sending incremental column commands to the VGA
 * controller after a player has lost the game (hit a foe).
 */
void lose_game() {
    for (int delay = 0; delay < 600000; delay++);
    for (int j = 240; j >= 0; j -= 2) {
        for (int i = 0; i < 320; i++) {
            send_column_cmd(i, i, j);
            for (int k = 0; k < 200; k++);
        }
        frame_done();
    }
}

/**
 * @brief Triggers the victory animation.
 * Spawns a dummy "WinCube" that spins and moves toward the camera,
 * signaling that all friendly cubes have been collected.
 */
void win_game() {
    CubeEntity WinCube;

    WinCube.friend = true;
    WinCube.active = true;
    WinCube.offset_x = 0;
    WinCube.z = TO_FP(WALL_SIZE);
    playerAngleIndex = 0;

    for (int dist = 1000; dist > 250; dist -= 4) {
        for (int i = 0; i < 320; i++) {
            send_column_cmd(i, i, 0);
        }
        int32_t calc_height = 2400 / dist;
        if (calc_height > 255) calc_height = 255;

        WinCube.offset_y = dist;
        WinCube.height = TO_FP(calc_height);
        WinCube.z = TO_FP(2 * WALL_SIZE);
        WinCube.yaw++;
        WinCube.pitch++;
        WinCube.roll++;

        render_cube(&WinCube);
        for (volatile int k = 0; k < 5000; k++);

        frame_done();
    }
}

/**
 * @brief Sets initial game state and entity behaviors.
 * Locates the player, spawns cubes, and assigns unique movement/rotation
 * behaviors to friendly and foe entities (e.g., foes bounce, friends spin).
 */
void init_game() {
    initPlayer();
    init_entities();
    for (int i = 0; i < MAX_ACTIVE_CUBES; i++) {
        if (world_cubes[i].active && world_cubes[i].friend) {
            world_cubes[i].dpitch = i % 2;
            world_cubes[i].droll = (i >> 2) && 0x1;
            world_cubes[i].dyaw = (i >> 3) && 0x1;
        }
        else if (world_cubes[i].active) {
            world_cubes[i].dx = 90000;
            world_cubes[i].dy = 70000;
        }
    }
}

/**
 * @brief Main Entry Point.
 * Initializes hardware registers, calculates delta time for smooth movement,
 * and executes the infinite game loop containing the update/render cycle.
 */
int main() {
    set_control_reg(true, true);
    while (1) {
        init_game();
        uint32_t last_time = get_time();
        int initial_foes = count_cubes(false);

        // Reset GPU command buffer
        WRITE_REG(GPU_CFD_ADR, 0);

        while (1) {
            uint32_t current_time = get_time();
            uint32_t delta_time = current_time - last_time;
            last_time = current_time;

            // Frame-rate independence multiplier (approximate fixed-point math)
            fixed32 dt_mult = (delta_time * 161) >> 9;

            readInputs();
            updatePlayer(dt_mult);
            updateRaycaster();

            // 3D Entity Pipeline: Project -> Sort (Painter's Algorithm) -> Render
            int found_cubes = get_cubes_camera_offsets(visibleList, MAX_ACTIVE_CUBES);
            sort_cubes(visibleList, found_cubes);

            for (int i = 0; i < found_cubes; i++) {
                render_cube(visibleList[i]);
            }

            update_cubes();

            // Win Condition: All friends collected
            if (count_cubes(true) == 0) {
                win_game();
                break;
            }

            // Lose Condition: A foe cube was "collected" (eaten)
            if (count_cubes(false) != initial_foes) {
                lose_game();
                break;
            }
            frame_done();
        }
    }
    return 0;
}