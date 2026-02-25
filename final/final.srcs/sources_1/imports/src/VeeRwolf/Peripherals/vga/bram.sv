`timescale 1ns / 1ps



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
    
    initial begin
        $readmemh("image.mem", memory);
    end
endmodule
