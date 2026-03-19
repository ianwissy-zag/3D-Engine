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
 * Author:      Ian Wyse, with assitance from Google Gemini
 * Date:        March 18, 2026
 * ========================================================================== */

module bram#(
    parameter DATA_WIDTH = 12,
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
    
    (* ram_style = "block" *) 
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
        $readmemh("image.mem", memory);
    end
endmodule
