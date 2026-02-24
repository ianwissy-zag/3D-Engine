`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/23/2026 03:33:14 PM
// Design Name: 
// Module Name: bram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module bram#(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 76800,
    parameter ADR_WIDTH = 17
    )(
    input logic                     vga_clk,
    input logic                     gpu_clk,
    input logic [DATA_WIDTH-1:0]    data_in,
    output logic [DATA_WIDTH-1:0]   data_out,
    input logic                     rd_en,
    input logic                     wr_en,
    input logic[ADR_WIDTH-1:0]      adr_wr,
    input logic [ADR_WIDTH-1:0]     adr_rd
    );
    
    (* ram_style = "block" *) 
    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    
    always_ff @(posedge vga_clk)begin
        if (rd_en) begin
            data_out <= memory[adr_rd];
        end
    end
    
    always_ff @(posedge gpu_clk) begin
        if (wr_en) begin
            memory[adr_wr] <= data_in;
        end
    end
    
    integer x, y;
    integer addr;

    initial begin
        // 1. First, clear the entire memory to black (0x00)
        for (addr = 0; addr < DEPTH; addr = addr + 1) begin
            memory[addr] = 8'h00;
        end

        // 2. Define a box in the center
        // Center of 320 is 160. Box from 140 to 180.
        // Center of 240 is 120. Box from 100 to 140.
        for (y = 100; y < 140; y = y + 1) begin
            for (x = 140; x < 180; x = x + 1) begin
                // Calculate the 1D index
                addr = (y * 320) + x;
                // Write "Full On" white (assuming 8-bit grayscale/RGB332)
                memory[addr] = 8'hFF; 
            end
        end
    end
endmodule
