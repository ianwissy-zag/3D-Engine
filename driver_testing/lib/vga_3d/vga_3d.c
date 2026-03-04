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

void new_frame() {

}

bool send_point_cmd(point_t data, uint8_t idx) {
    // See if there is room in the Command FIFO
    if (is_fifo_full()) {
        return false;
    }

    // Target the GPU Command Register
    uint32_t addr = VGA_BASEADDR + VGA_CMD_REG;

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

// TODO: This is placeholder code for sending a draw command to the Command FIFO. 
bool send_draw_cmd() {
    // See if there is room in the Command FIFO
    if (is_fifo_full()) {
        return false;
    }

    // Target the GPU Command Register
    uint32_t addr = VGA_BASEADDR + VGA_CMD_REG;

    // Prepare Command Register fields


    // Compile data to be written to the Command Register
    uint32_t reg;

    //Write to the GPU
    WRITE_REG(addr, reg);

    return true;
}

// TODO: This is placeholder code for drawing triangles on the screen. Not super nice...
bool draw_triangle(triangle_t tri, uint8_t color) {
    // Send point data
    while (send_point(tri.a, 0));
    while (send_point(tri.b, 1));
    while (send_point(tri.c, 2));

    // Send color data
    while (send_color(color));

    // Tell GPU that to start drawing the triangle
    while (send_draw_cmd());

    return true;
}