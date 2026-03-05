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
#include <stdbool.h>

/* VGA GPU Defines -------------------------------------------------------------------------------- */
// Base Address
#define VGA_BASEADDR            0x80001500
// Register Offsets
#define VGA_BUF_IDX_REG         0x00    // Frame (BRAM) Buffer Index Register   (Read Only)
#define VGA_COL_REG             0x04    // Column Drawing Register              (Read and Write)
#define VGA_FCD_REG             0x08    // Frame Calculation Done Register      (Write Only)
#define VGA_STATUS_REG          0x0C    // GPU Status Register                  (Read Only)
#define VGA_CTRL_REG            0x10    // GPU Control Register                 (Read and Write)
#define VGA_CMD_REG             0x14    // GPU Command Register                 (Write Only)

/* VGA GPU Register Masks ------------------------------------------------------------------------- */ 
// Frame Buffer Index Register
// None

// Column Drawing Register
#define VGA_COL_WR_TOG_MASK     0x02000000
#define VGA_COL_HEIG_MASK       0x01FE0000
#define VGA_COL_COLOR_MASK      0x0001FE00
#define VGA_COL_PIX_MASK        0x000001FF

// Frame Calculation Done Register
// None

// GPU Status Register
#define VGA_STATUS_OVERF_MASK   0x00000008
#define VGA_STATUS_EMPTY_MASK   0x00000004
#define VGA_STATUS_FULL_MASK    0x00000002
#define VGA_STATUS_BUSY_MASK    0x00000001

// GPU Control Register
#define VGA_CTRL_OVERL_MASK     0x00000008
#define VGA_CTRL_C_ERR_MASK     0x00000004
//#define VGA_CTRL_CFIFO_MASK     0x00000002    Not implemented
#define VGA_CTRL_MODE_MASK      0x00000001

// GPU Command Register
#define VGA_CMD_OP_MASK         0xC0000000
#define VGA_CMD_POINT_MASK      0x0001FFFF
#define VGA_CMD_X_MASK          0x0001FF00
#define VGA_CMD_Y_MASK          0x000000FF
#define VGA_CMD_COLOR_MASK      0x000000FF

/* Additional VGA GPU Command Register Defines ---------------------------------------------------- */
// Op Codes
#define VGA_CMD_OP_POINT0       0x0
#define VGA_CMD_OP_POINT1       0x1
#define VGA_CMD_OP_POINT2       0x2
#define VGA_CMD_OP_COLOR        0x3

// Command Register Field Offsets
#define VGA_CMD_OP_OFFSET       30
#define VGA_CMD_X_OFFSET        8
#define VGA_CMD_Y_OFFSET        0
#define VGA_CMD_COLOR_OFFSET    0

/* Macro Definitions ------------------------------------------------------------------------------ */
// Read and write macros
#define READ_REG(dir)           (*(volatile unsigned *)dir)
#define WRITE_REG(dir, value)   { (*(volatile unsigned *)dir) = (value); }

/* Data Structures -------------------------------------------------------------------------------- */
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

/* Function Declarations -------------------------------------------------------------------------- */
// L0 Commands
bool is_cmd_full();
bool is_cmd_empty();
void new_frame();
bool send_point_cmd(point_t p, uint8_t idx);
bool send_color_cmd(uint8_t color);
bool send_draw_cmd();
// L1 Commands
bool draw_triangle(triangle_t tri, uint8_t color);

#endif // VGA_3D_H