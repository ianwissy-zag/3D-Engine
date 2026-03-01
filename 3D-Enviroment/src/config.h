#ifndef CONFIG_H
#define CONFIG_H

#include <stdlib.h>

/* Misc. constants */
#define FALSE 0
#define TRUE  1

/* Window parameters*/
#define WINDOW_WIDTH  320
#define WINDOW_HEIGHT 240

/* Raycaster parameters */
#define TEXTURE_SIZE           64
#define WALL_SIZE              64
#define PLAYER_SIZE            20
#define PLAYER_MOVEMENT_SPEED  3
#define ROT_SPEED_INT          1

/* Map constants */
#define MAP_GRID_WIDTH    10
#define MAP_GRID_HEIGHT   10
#define MAP_PIXEL_WIDTH   (MAP_GRID_WIDTH * WALL_SIZE)
#define MAP_PIXEL_HEIGHT  (MAP_GRID_HEIGHT * WALL_SIZE)

/* Map wall types */
#define P            -1  
#define R             1  

/* Globals */
extern const short MAP[MAP_GRID_HEIGHT][MAP_GRID_WIDTH];

#endif /* CONFIG_H */
