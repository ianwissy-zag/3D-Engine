/* ==========================================================================
 * Module Name: vga
 *
 * Description: 
 * A VGA display controller that interfaces with a frame buffer (BRAM) to 
 * drive a 640x480 screen. It incorporates a Display Timing Generator (DTG) 
 * to create horizontal and vertical sync signals. 
 * * Key Features:
 * - Resolution Scaling: Scales a 320x240 internal frame buffer up to a 
 * 640x480 physical display by shifting pixel row/col values (pixel doubling).
 * - Double Buffering Support: Monitors 'fcd' (frame complete/flip) and 'busy' 
 * signals to safely swap the active BRAM buffer (`bram_inx`) during the 
 * vertical blanking interval (row 480).
 * - Pipeline Synchronization: Delays sync signals (hsync, vsync, px_en) by 
 * two clock cycles to account for BRAM read latency, ensuring that the 
 * fetched pixel data aligns perfectly with the active display area.
 *
 * Parameters:
 * - WIDTH  : Physical screen width (Default: 640)
 * - HEIGHT : Physical screen height (Default: 480)
 *
 * Interface Notes:
 * - 'data' [11:0]  : 12-bit color data from BRAM (Format: 4-4-4 RGB).
 * - 'rd_adr' [16:0]: 17-bit linearized address to fetch from the frame buffer.
 * - 'fcd' / 'busy' : Handshake signals from the GPU/CPU to coordinate frame flipping.
 *
 * Author:      Ian Wyse with assistance from Google Gemini
 * Date:        March 18, 2026
 * ========================================================================== */
 
 module vga #(
    parameter WIDTH = 640, 
    parameter HEIGHT = 480
)(
    // Interface to BRAM (Frame Buffer)
    output logic                    rd_en,
    output logic [16:0]             rd_adr,
    output logic                    bram_inx,
    input  logic [11:0]             data,

    // VGA Physical Interface
    input  logic                    clk_vga,    
    input  logic                    rst,
    output logic [3:0]              VGA_Red,
    output logic [3:0]              VGA_Green,
    output logic [3:0]              VGA_Blue,
    output logic                    vsync,
    output logic                    hsync,
    
    // Handshake signals for frame flipping
    input  logic                    fcd,  // Frame Complete pulse from GPU/CPU
    input  logic                    busy  // GPU busy flag
);

    // Internal wires from the Display Timing Generator (DTG)
    logic        hsync_dtg;
    logic        vsync_dtg;
    logic        px_en_dtg;
    logic [10:0] pixel_row;
    logic [10:0] pixel_col;

    // Instantiate the Display Timing Generator to handle the 640x480 standard timing
    dtg dgt_instance(
      .clock        (clk_vga),
      .rst          (rst), 
      .horiz_sync   (hsync_dtg),
      .vert_sync    (vsync_dtg),
      .video_on     (px_en_dtg),
      .pixel_row    (pixel_row),
      .pixel_column (pixel_col)
    );

    // Resolution Scaling (Pixel Doubling)
    // Shift right by 1 divides the 640x480 physical coordinates by 2,
    // resulting in a 320x240 logical coordinate space.
    logic [8:0] scaled_x; 
    logic [7:0] scaled_y; 
    assign scaled_x = pixel_col[9:1]; 
    assign scaled_y = pixel_row[8:1]; 
    
    // Synchronize the 'fcd' and 'busy' signals into the VGA clock domain.
    // These signals likely originate from the GPU/CPU running on a different clock.
    logic fcd_meta, fcd_sync;
    logic busy_meta, busy_sync;
    
    always_ff @(posedge clk_vga) begin
        if (rst) begin
            fcd_meta  <= 1'b0;
            fcd_sync  <= 1'b0;
            busy_meta <= 1'b0;
            busy_sync <= 1'b0;
        end else begin
            fcd_meta  <= fcd;
            fcd_sync  <= fcd_meta;
            busy_meta <= busy;
            busy_sync <= busy_meta;
        end
    end
   
    // Only allow a buffer swap if a new frame is complete AND the GPU isn't currently drawing
    logic enable_flip;
    assign enable_flip = fcd_sync && !busy_sync;

    // Double-Buffering Logic
    // Wait until we hit the start of the front porch (pixel_col == 0 && pixel_row == 480)
    // to swap buffers. This guarantees the swap happens during the vertical blanking 
    // interval, eliminating visual screen tearing.
    always_ff @(posedge clk_vga) begin
        if (rst) begin
            bram_inx <= 0;
        end else if (pixel_col == 0 && pixel_row == 480 && enable_flip) begin
            bram_inx <= ~bram_inx;
        end
    end
    
    // Address Generation for BRAM
    always_ff @(posedge clk_vga) begin
        if (rst) begin
            rd_adr <= 17'd0;
            rd_en  <= 1'b0;
        end else begin
            // Linearize the 2D scaled coordinates (X, Y) into a 1D memory address.
            // Math: Y * 320 + X. 
            // We use shifts instead of a multiplier: (Y * 256) + (Y * 64) + X.
            rd_adr <= ({9'd0, scaled_y} << 8) + ({9'd0, scaled_y} << 6) + {8'd0, scaled_x};
            
            // Read from BRAM only when the DTG says we are actively outputting pixels
            rd_en  <= px_en_dtg;
        end
    end

    // Pipeline Synchronization
    // BRAM inherently takes 2 clock cycles to output data after an address is presented.
    // We must delay the hsync, vsync, and video_on signals by exactly 2 cycles 
    // so they align perfectly with the pixel data coming out of the BRAM.
    logic hsync_d1, hsync_d2;
    logic vsync_d1, vsync_d2;
    logic px_en_d1, px_en_d2;

    always_ff @(posedge clk_vga) begin
        if (rst) begin
            {hsync_d2, hsync_d1} <= '0;
            {vsync_d2, vsync_d1} <= '0;
            {px_en_d2, px_en_d1} <= '0;
        end else begin
            hsync_d1 <= hsync_dtg;
            hsync_d2 <= hsync_d1;
            
            vsync_d1 <= vsync_dtg;
            vsync_d2 <= vsync_d1;
            
            px_en_d1 <= px_en_dtg;
            px_en_d2 <= px_en_d1;
        end
    end

    // Output the sync signals to the monitor
    assign hsync = hsync_d2;
    assign vsync = vsync_d2;

    // Output Color Data
    // Only output the BRAM color data when inside the active screen area (px_en_d2).
    // Otherwise, drive the lines to 0 (black) during the blanking intervals.
    always_comb begin
        if (px_en_d2) begin
            VGA_Red   = data[11:8];
            VGA_Green = data[7:4];
            VGA_Blue  = data[3:0];
        end else begin
            VGA_Red   = 4'd0;
            VGA_Green = 4'd0;
            VGA_Blue  = 4'd0;
        end
    end

endmodule