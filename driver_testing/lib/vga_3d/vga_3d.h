/**
 * @file vga_3d.h
 * 
 * @brief This is a driver header file for a custom VGA Graphics card.
 * 
 * @author Hunter Drake (hgd@pdx.edu)
 * @date 3/2/2026
 */

#ifndef VGA_3D_H
#define VGA_3D_H

#include <stdint.h>

/* VGA GPU Defines */
// Base Address
#define VGA_BASEADDR        0x80001500
// Register Offsets
#define VGA_BUF_IDX_REG     0x00    // Frame (BRAM) Buffer Index Register   (Read Only)
#define VGA_COL_REG         0x04    // Column Drawing Register              (Read and Write)
#define VGA_FCD_REG         0x08    // Frame Calculation Done Register      (Write Only)
#define VGA_STATUS_REG      0x0C    // GPU Status Register                  (Read Only)
#define VGA_CTRL_REG        0x10    // GPU Control Register                 (Read and Write)
#define VGA_CMD_REG         0x14    // GPU Command Register                 (Write Only)

/* VGA GPU Register Masks */ 
// Frame Buffer Index Register
// None

// Column Drawing Register
#define VGA_COL_WR_TOG_MASK 0x02000000
#define VGA_COL_HEIG_MASK   0x01FE0000
#define VGA_COL_COLOR_MASK  0x0001FE00
#define VGA_COL_PIX_MASK    0x000001FF

// Frame Calculation Done Register
// None

// GPU Status Register
#define VGA_STAT_OVERF_MASK 0x00000008
#define VGA_STAT_EMPTY_MASK 0x00000004
#define VGA_STAT_FULL_MASK  0x00000002
#define VGA_STAT_BUSY_MASK  0x00000001

// GPU Control Register
#define VGA_CTRL_OVERL_MASK 0x00000008
#define VGA_CTRL_C_ERR_MASK 0x00000004
//#define VGA_CTRL_CFIFO_MASK 0x00000002    Not implemented
#define VGA_CTRL_MODE_MASK  0x00000001

// GPU Command Register
// None

/* Data Structures */
// Shape/Triangle Structures
typedef struct {
    uint16_t x;
    uint16_t y;
} point_t;

typedef struct {
    point_t a;
    point_t b;
    point_t c;
} triangle_t;

/* Function Declarations */
void new_frame();
void draw_triangle(triangle_t tri, uint8_t color);

#endif