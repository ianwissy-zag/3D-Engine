#include "vga_3d.h"

bool is_fifo_full() {
    // Target the GPU Status Register
    uint32_t addr = VGA_BASEADDR + VGA_STATUS_REG;

    // Read the GPU's status
    uint32_t reg = READ_REG(addr);

    return reg & VGA_STATUS_FULL_MASK;
}

bool is_fifo_empty() {
    // Target the GPU Status Register
    uint32_t addr = VGA_BASEADDR + VGA_STATUS_REG;

    // Read the GPU's status
    uint32_t reg = READ_REG(addr);

    return reg & VGA_STATUS_EMPTY_MASK;
}

void frame_done() {
    // Target the GPU Frame Calculation Done Register
    uint32_t addr = VGA_BASEADDR + VGA_FCD_REG;

    // Indicate completed frame
    WRITE_REG(addr, 0x00000001);

    // Clear FCD Register for next completed frame
    WRITE_REG(addr, 0x00000000);
}

bool send_point_cmd(point_t data, uint8_t idx) {
    // See if there is room in the Command FIFO
    if (is_fifo_full()) {
        return false;
    }

    // Target the GPU Command Register
    uint32_t addr = VGA_BASEADDR + VGA_CMD_REG;

    // Make sure the point index is valid (0 through 2)
    if (idx > 2) {
        return false;
    }

    // Prepare Command Register fields
    uint32_t x = ((uint32_t) data.x << VGA_CMD_X_OFFSET) & VGA_CMD_X_MASK;
    uint32_t y = ((uint32_t) data.y << VGA_CMD_Y_OFFSET) & VGA_CMD_Y_MASK;
    uint32_t op = ((uint32_t) idx << VGA_CMD_OP_OFFSET) & VGA_CMD_OP_MASK;

    // Compile data to be written to the Command Register
    uint32_t reg = op | x | y;

    // Write to the GPU
    WRITE_REG(addr, reg);

    return true;
}

bool send_color_cmd(uint8_t data) {
    // See if there is room in the Command FIFO
    if (is_fifo_full()) {
        return false;
    }

    // Target the GPU Command Register
    uint32_t addr = VGA_BASEADDR + VGA_CMD_REG;

    // Prepare Command Register fields
    uint32_t color = ((uint32_t) data << VGA_CMD_COLOR_OFFSET) & VGA_CMD_COLOR_MASK;
    uint32_t op = ((uint32_t) VGA_CMD_OP_COLOR << VGA_CMD_OP_OFFSET) & VGA_CMD_OP_MASK;

    // Compile data to be written to the Command Register
    uint32_t reg = op | color;

    // Write to the GPU
    WRITE_REG(addr, reg);

    return true;
}

bool send_column_cmd(uint16_t p_col, uint8_t color, uint8_t height) {
    // Ensure that the pixel column is valid
    if (p_col > (VGA_SCREEN_WIDTH - 1)) {
        p_col = VGA_SCREEN_WIDTH - 1;
    }

    // Ensure that the column height is valid
    if (height > VGA_SCREEN_HEIGHT) {
        height = VGA_SCREEN_HEIGHT;
    }

    // Target Column Drawing Register
    uint32_t addr = VGA_BASEADDR + VGA_COL_REG;

    // Prepare Column Drawing Fields
    uint32_t pixel_column = ((uint32_t) p_col << VGA_COL_PIX_OFFSET) & VGA_COL_PIX_MASK;
    uint32_t column_color = ((uint32_t) color << VGA_COL_COLOR_OFFSET) & VGA_COL_COLOR_MASK;
    uint32_t column_height = ((uint32_t) height << VGA_COL_HEIG_OFFSET) & VGA_COL_HEIG_MASK;

    // Compile data to be written to the Column Drawing Register
    uint32_t reg = pixel_column | column_color | column_height;

    // Write to the GPU
    WRITE_REG(addr, reg);

    return true;
}

// TODO: This is placeholder code for drawing triangles on the screen. Not super nice...
bool draw_triangle(triangle_t tri, uint8_t color) {
    // Send point data
    while (!send_point_cmd(tri.a, 0));
    while (!send_point_cmd(tri.b, 1));
    while (!send_point_cmd(tri.c, 2));

    // Send color data which tells GPU to start drawing the triangle
    while (!send_color_cmd(color));

    return true;
}