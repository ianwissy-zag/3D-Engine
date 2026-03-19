/* ==========================================================================
 * Module Name: bram
 *
 * Description: 
 * A dual-port, dual-clock Block RAM (BRAM) module configured as a 
 * double-buffered frame buffer for a graphics pipeline. 
 *
 * Key Features:
 * - Double Buffering: The memory space is sized to 2x the DEPTH. It uses 
 * an index toggle to ensure the VGA controller reads from one half of the 
 * memory while the GPU writes to the opposite half, preventing screen tearing.
 * - Clock Domain Crossing (CDC): Uses a 2-stage synchronizer to safely 
 * pass the active buffer index (vga_bram_inx) from the vga_clk domain 
 * into the gpu_clk domain.
 * - True Dual-Port: Independent read and write ports operating on separate 
 * clocks (vga_clk and gpu_clk) to support asynchronous display and 
 * render rates.
 *
 * Parameters:
 * - DATA_WIDTH : Width of the pixel data, usually 12-bit RGB (Default: 12)
 * - DEPTH      : Number of pixels in a single frame buffer (Default: 76800, 
 * which corresponds to a 320x240 resolution)
 * - ADR_WIDTH  : Number of bits needed to address DEPTH (Default: 17)
 *
 * Author:      Ian Wyse, with assistance from Google Gemini
 * Date:        March 18, 2026
 * ========================================================================== */

`timescale 1ns / 1ps

module bram#(
    parameter DATA_WIDTH = 12,
    parameter DEPTH      = 76800, // 320 * 240 pixels
    parameter ADR_WIDTH  = 17     // 2^17 = 131,072 (enough for 76,800)
    )(
    // VGA display clock domain
    input logic                 vga_clk,
    
    // GPU rendering clock domain
    input logic                 gpu_clk,
    input logic                 gpu_rst,
    
    // Buffer indexing signals for double-buffering
    input logic                 vga_bram_inx, // Tells us which half VGA is reading
    output logic                gpu_bram_inx, // Tells the GPU which half it can write to
    
    // Memory interface
    input logic [DATA_WIDTH-1:0]  data_in,  // Pixel data from GPU
    output logic [DATA_WIDTH-1:0] data_out, // Pixel data to VGA
    input logic                   rd_en,    // VGA read enable
    input logic                   wr_en,    // GPU write enable
    input logic [ADR_WIDTH-1:0]   adr_wr,   // GPU write address (0 to DEPTH-1)
    input logic [ADR_WIDTH-1:0]   adr_rd    // VGA read address (0 to DEPTH-1)
    );
    
    // Synchronizer registers for passing vga_bram_inx into the gpu_clk domain
    logic sync_0, sync_1;
    
    // Clock Domain Crossing (CDC) and Buffer Inversion
    always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
            sync_0       <= '0;
            sync_1       <= '0;
            gpu_bram_inx <= '1; // Default GPU to buffer 1
        end
        else begin
            sync_0       <= vga_bram_inx; // Stage 1
            sync_1       <= sync_0;       // Stage 2 (safe to use)
            gpu_bram_inx <= ~sync_1;      // Invert so GPU writes to the opposite buffer
        end
    end
    
    // Actual BRAM declaration. A single block of size double the frame buffer size is used. 
    (* ram_style = "block" *) 
    logic [DATA_WIDTH-1:0] memory [0:(2*DEPTH)-1];
    
    // Address Calculation
    // Combine the 0-to-DEPTH address with the buffer index to get the absolute memory address.
    // If inx is 0, we write/read from 0 to DEPTH-1.
    // If inx is 1, we write/read from DEPTH to (2*DEPTH)-1.
    logic [17:0] full_rd_adr, full_wr_adr;
    assign full_rd_adr = adr_rd + (vga_bram_inx * DEPTH);
    assign full_wr_adr = adr_wr + (gpu_bram_inx * DEPTH);
    
    // VGA Read Port (Synchronous to vga_clk)
    always_ff @(posedge vga_clk) begin
        if (rd_en) data_out <= memory[full_rd_adr];
    end
    
    // GPU Write Port (Synchronous to gpu_clk)
    always_ff @(posedge gpu_clk) begin
        if (wr_en) begin
            memory[full_wr_adr] <= data_in;
        end
    end
    
    // Pre-load the memory with an initial image
    initial begin
        $readmemh("image.mem", memory);
    end
endmodule