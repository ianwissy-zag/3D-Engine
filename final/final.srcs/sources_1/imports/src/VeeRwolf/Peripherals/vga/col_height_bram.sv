`timescale 1ns / 1ps

module z_bram #(
    parameter int SCREEN_WIDTH = 320
)(
    input  logic       clk,
    
    // Write Port 
    input  logic       we,
    input  logic [8:0] wr_adr,  // 0 to 319
    input  logic [9:0] wr_data, // Column height
    
    // Read Port 
    input logic        re,
    input  logic [8:0] rd_adr,
    output logic [9:0] rd_data
);

    // BRAM array: 320 elements, 10 bits wide
    logic [9:0] ram [0:SCREEN_WIDTH-1];

    initial begin
        for (int i = 0; i < SCREEN_WIDTH; i++) begin
            ram[i] = '0;
        end
    end

    // Write
    always_ff @(posedge clk) begin
        if (we) begin
            ram[wr_adr] <= wr_data;
        end
    end
    
    // Read
    always_ff @(posedge clk) begin
        if (re) begin
            rd_data <= ram[rd_adr];
        end
    end
endmodule
