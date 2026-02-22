#ifndef PLAYER_H
#define PLAYER_H

#include <stdint.h>
#include "linalg.h"
#include "raycaster.h" /* Included for the fixed32 definition */

/* Global float data (The Bridge - read by renderer) */
extern Vector3f playerPos;
extern Vector3f playerDir;

/* Global toggles */
extern char movingForward;
extern char movingBack;
extern char turningLeft;
extern char turningRight;
extern char playerIsRunning;

#ifndef FIXED32_DEFINED
#define FIXED32_DEFINED
typedef int32_t fixed32;
#endif

/* Functions */

/**
 * Initialize the player.
 */
void initPlayer();

/**
 * Update the player for the current frame.
 */
void updatePlayer();

/**
 * Move the player by a given movement vector.
 *
 * dx: The x component of the movement vector (16.16 fixed-point).
 * dy: The y component of the movement vector (16.16 fixed-point).
 */
void movePlayer(fixed32 dx, fixed32 dy);

/**
 * Check if a given movement vector intersects with the world
 * and should be clipped.
 *
 * dx: The x component of the movement vector to check (16.16 fixed-point).
 * dy: The y component of the movement vector to check (16.16 fixed-point).
 *
 * Returns: Zero if the vector should not be clipped, non-zero otherwise.
 */
int clipMovement(fixed32 dx, fixed32 dy);

#endif /* PLAYER_H */