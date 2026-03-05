`timescale 1ns / 1ps



module bram#(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 76800,
    parameter ADR_WIDTH = 17
    )(
    input logic                     vga_clk,
    input logic                     gpu_clk,
    input logic                     gpu_rst,
    
    input logic                     vga_bram_inx,
    output logic                    gpu_bram_inx,
    
    input logic [DATA_WIDTH-1:0]    data_in,
    output logic [DATA_WIDTH-1:0]   data_out,
    input logic                     rd_en,
    input logic                     wr_en,
    input logic[ADR_WIDTH-1:0]      adr_wr,
    input logic [ADR_WIDTH-1:0]     adr_rd
    );
    
    logic sync_0, sync_1;
    
    // CDC and inversion
    always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
            sync_0       <= '0;
            sync_1       <= '0;
            gpu_bram_inx <= '1;
        end
        else begin
            sync_0       <= vga_bram_inx;
            sync_1       <= sync_0;
            gpu_bram_inx <= ~sync_1; 
        end
    end
    
    (* ram_style = "block", cascade_height = 1 *) 
    logic [DATA_WIDTH-1:0] memory [0:(2*DEPTH)-1];
    
    
    logic [17:0] full_rd_adr, full_wr_adr;
    assign full_rd_adr = adr_rd + (vga_bram_inx * DEPTH);
    assign full_wr_adr = adr_wr + (gpu_bram_inx * DEPTH);
    
    always_ff @(posedge vga_clk) begin
        if (rd_en) data_out <= memory[full_rd_adr];
    end
    
    always_ff @(posedge gpu_clk) begin
        if (wr_en) begin
            memory[full_wr_adr] <= data_in;
        end
    end
    
    initial begin
        $readmemh("icon.mem", memory);
    end
endmodule
