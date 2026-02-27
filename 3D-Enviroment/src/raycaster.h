#ifndef RAYCASTER_H
#define RAYCASTER_H

#include "config.h"
#include <stdint.h>

/* Fixed-Point Macros */
typedef int32_t fixed32;
#define FP_SHIFT 16
#define TO_FP(x) ((fixed32)((x) * (1 << FP_SHIFT)))
#define IMUL(a, b) ((fixed32)(((int64_t)(a) * (b)) >> FP_SHIFT))
#define IDIV(a, b) ((fixed32)(((int64_t)(a) << FP_SHIFT) / (b)))
#define IABS(x) ((x) < 0 ? -(x) : (x))

#define FOV_TAN_CONST 37837
#define LUT_STEPS 256

#define VIEWPLANE_LENGTH WINDOW_WIDTH

// THis shift ammount is associated with a wall size of 64
#define WALL_SHIFT 6 

extern const int32_t SIN_LUT[];
extern const int32_t COS_LUT[];

void run_integer_raycast();
void updateRaycaster();

#endif /* RAYCASTER_H */
