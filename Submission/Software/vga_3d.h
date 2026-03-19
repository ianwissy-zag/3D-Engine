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
// Screen Dimensions
#define VGA_SCREEN_WIDTH        320
#define VGA_SCREEN_HEIGHT       240

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
#define VGA_CMD_X_MASK          0x3FF80000
#define VGA_CMD_Y_MASK          0x0007FE00
#define VGA_CMD_COLOR_MASK      0x3FFC0000
#define VGA_CMD_HEIGHT_MASK     0x0003FC00

/* Additional VGA GPU Defines --------------------------------------------------------------------- */
// Column Drawing Register
#define VGA_COL_WR_TOG_OFFSET   25
#define VGA_COL_HEIG_OFFSET     17
#define VGA_COL_COLOR_OFFSET    9
#define VGA_COL_PIX_OFFSET      0

// Command Register Op Codes
#define VGA_CMD_OP_POINT0       0x0
#define VGA_CMD_OP_POINT1       0x1
#define VGA_CMD_OP_POINT2       0x2
#define VGA_CMD_OP_COLOR        0x3

// Command Register Field Offsets
#define VGA_CMD_OP_OFFSET       30
#define VGA_CMD_X_OFFSET        19
#define VGA_CMD_Y_OFFSET        9
#define VGA_CMD_COLOR_OFFSET    18
#define VGA_CMD_HEIGHT_OFFSET   10

/* Macro Definitions ------------------------------------------------------------------------------ */
// Read and write macros
#define READ_REG(dir)           (*(volatile unsigned *)dir)
#define WRITE_REG(dir, value)   { (*(volatile unsigned *)dir) = (value); }

/* Data Structures -------------------------------------------------------------------------------- */
// Shape/Triangle Structures
typedef struct {
    int16_t x;
    int16_t y;
} point_t;

typedef struct {
    point_t a;
    point_t b;
    point_t c;
} triangle_t;

/* Function Declarations -------------------------------------------------------------------------- */

/**
 * @brief   is_cmd_full() determines if the 3D Command FIFO is full.
 * * @details This function reads the GPU Status Register and determines if the 3D Command FIFO is full.
 * * @return   Returns true if the 3D Command FIFO is full. Returns false otherwise.
 */
bool is_cmd_full();

/**
 * @brief   is_cmd_empty() determines if the 3D Command FIFO is empty.
 * * @details This function reads the GPU Status Register and determines if the 3D Command FIFO is 
 * empty.
 * * @return   Returns true if the 3D Command FIFO is empty. Returns false otherwise.
 */
bool is_cmd_empty();

/**
 * @brief   set_control_reg() sets control fields in the GPU Control Register that dictate the GPU's
 * behavior.
 * * @param   overlay_en:     Enable for overlay
 * * @param   prim_mode_en:   Enable for primitive mode
 * * @return   There is no return value
 */
void set_control_reg(bool overlay_en, bool prim_mode_en);

/**
 * @brief   frame_done() tells the GPU that this frame is done being drawn and to switch to the next 
 * frame so it can be drawn.
 * * @details This function writes to the Frame Calculation Done Register. This tells the GPU that the 
 * contents of the currently selected BRAM can be shown on the screen and that future writes 
 * are to be directed to the other BRAM.
 * * @return   There is no return value.
 */
void frame_done();

/**
 * @brief   send_point_cmd() sends 1 point of a triangle to the GPU.
 * * @details This function sends an indexed point of the triangle numbered 0 through 2 to the 3D 
 * Command FIFO for processing by the GPU.
 * * @note    It is important that point data be written to the 3D Command FIFO before the color data. 
 * This is because sending color data to the 3D Command FIFO also starts the triangle 
 * rasterization process.
 * * @param   p:      A point_t struct that contains the x and y point data for a vertex of the triangle.
 * * @param   idx:    A index marking what point of the trianlge it is. It can be 0, 1, or 2.
 *
 * @return   Returns true if the point data was sent successfully. Returns false if the 3D Command FIFO
 * is full and can't accept more commands at the moment.
 */
bool send_point_cmd(point_t p, uint8_t idx);

/**
 * @brief   send_color_cmd() sends the color of the triangle to the GPU and starts the rasterization 
 * process.
 * * @details This function sends a 12-bit color to the 3D Command FIFO. The 12-bit color is typically 
 * mapped as {rrrrggggbbbb}.
 * * @note    It is important that point data be written to the 3D Command FIFO before the color data. 
 * This is because sending color data to the 3D Command FIFO also starts the triangle 
 * rasterization process.
 * * @param   data:   The 12-bit color of the triangle.
 * * @param   height_data: The height of the triangle.
 * * @return   Returns true if the color data was sent successfully. Returns false if the 3D Command FIFO
 * is full and can't accept more commands at the moment.
 */
bool send_color_cmd(uint16_t data, uint32_t height_data);

/**
 * @brief   send_column_cmd() sends a y-centered column to be drawn on the screen.
 * * @details This function sends a y-centered column to the Column Drawing Register. This in turn 
 * writes the rectangle data to the BRAM. 
 * * @param   p_col:  The pixel column that the rectangle is to be drawn in.
 * * @param   color:  The 8-bit color of the rectangle. (Update this if columns also use 12-bit color).
 * * @param   height: The height of the rectangle.
 * * @return   Returns true.
 */
bool send_column_cmd(uint16_t p_col, uint8_t color, uint8_t height);

/**
 * @brief   draw_triangle() send triangle data (points and color) to the GPU which rasterizes the 
 * triangle and puts that data into the BRAM.
 * * @details This function first sends point data and then color data to the 3D Command FIFO to 
 * rasterize the triangle. To make sure that the data is sent, the function waits until the 
 * 3D Command FIFO has room with a while loop.
 * * @param   tri:    A triangle_t struct that contains all of the triangle's point data.
 * * @param   color:  The 12-bit color of the triangle.
 * * @param   height: The 8-bit height of the triangle.
 * * @return   Returns true.
 */
bool draw_triangle(triangle_t tri, uint16_t color, uint8_t height);

#endif // VGA_3D_H