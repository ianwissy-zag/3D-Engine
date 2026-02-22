/*
* Author: Ian Wyse
* Date: 2/14/2026
* Wisihbone VGA Controller
* 
* Description: This module is a wishbone interfaced VGA controller. It 
* can output the characters 0-9 on a VGA monitor at any location on the monitor,
* in addition to being able to change the background color of the monitor to any
* desired color (with 4 bit resolution). 
*
* Register Map:
* 0x1: [19:10] Char Row (Y), [9:0] Char Col (X)
* 0x2: [11:0] Background Color (4-bit RGB)
* 0x3: [7:0] ASCII Character (Supports '0'-'9')
*
* Clock Domains:
* - wb_clk_i: Wishbone bus interface (12.5MHz)
* - clk_vga:  VGA Pixel Clock (typically 25.175MHz for 640x480)
* - Cross-domain synchronization handled via 2-stage FF synchronizers.
*
* Disclaimer: I used Google Gemini to provide possible structures and a recomendation
* on the correct/most effective clock domain crossing method to use in this module. 
* I also had it do an initial pass on this header block.
*/
module wb_vga #(
    parameter WIDTH = 640, 
    parameter HEIGHT = 480
)(
    // Wishbone interconnect (Slave Interface)
    input  logic                    wb_clk_i,
    input  logic                    wb_rst_i,
    input  logic [3:0]              wb_adr_i,
    input  logic [31:0]             wb_dat_i,
    output logic [31:0]             wb_dat_o,
    input  logic                    wb_we_i,
    input  logic [3:0]              wb_sel_i,
    input  logic                    wb_stb_i,
    input  logic                    wb_cyc_i,
    output logic                    wb_ack_o,

    // VGA Ports (Video Interface)
    input  logic                    clk_vga,    // Pixel Clock
    output logic [3:0]              VGA_Red,
    output logic [3:0]              VGA_Green,
    output logic [3:0]              VGA_Blue,
    output logic                    vsync,
    output logic                    hsync
);

    // =======================
    // Wishbone Side - 12.5kHz
    // =======================
    logic wb_valid_cycle, wb_write_en, wb_read_en;
    
    // Wishbone registers
    logic [9:0] wb_char_row;
    logic [9:0] wb_char_col;
    logic [11:0] wb_bg_color;
    logic [7:0] wb_char;

    // Control logic
    assign wb_valid_cycle = wb_cyc_i && wb_stb_i;
    assign wb_write_en    = wb_valid_cycle && wb_we_i && !wb_ack_o;
    assign wb_read_en     = wb_valid_cycle && !wb_we_i && !wb_ack_o;

    // Acknowledgement
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) 
            wb_ack_o <= 1'b0;
        else          
            wb_ack_o <= wb_valid_cycle && !wb_ack_o;
    end

    // Write
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_char_row <= '0;
            wb_char_col <= '0;
            wb_char     <= '0;
        end else if (wb_write_en) begin
            case (wb_adr_i)
                4'h1: begin // Position
                    wb_char_row <= wb_dat_i[19:10];
                    wb_char_col <= wb_dat_i[9:0];
                end
                4'h2: begin // Color
                    wb_bg_color <= wb_dat_i[11:0];
                end
                4'h3: begin // Character
                    wb_char     <= wb_dat_i[7:0];
                end
            endcase
        end
    end

    // Read
    always_ff @(posedge wb_clk_i) begin
        if (wb_read_en) begin
            case (wb_adr_i)
                4'h1:    wb_dat_o <= {12'b0, wb_char_row, wb_char_col};
                4'h2:    wb_dat_o <= {20'b0, wb_bg_color};
                4'h3:    wb_dat_o <= {24'b0, wb_char};
                default: wb_dat_o <= '0;
            endcase 
        end
        else wb_dat_o <= '0;
    end

    // =========================================================================
    // CDC Flip-flops, 2-stage
    // =========================================================================
    // I chose not to use a FIFO becausae the singals are infrequent with respect
    // to the clock frequency, and because a single cycle difference in arrival time
    // of parts of the data does not have a functional effect on the output. 
    
    // CDC flip-flop registers
    logic [9:0] vga_char_row, vga_char_row_meta;
    logic [9:0] vga_char_col, vga_char_col_meta;
    logic [11:0] vga_bg_color, vga_bg_color_meta;
    logic [7:0] vga_char,     vga_char_meta;
    logic       vga_rst,      vga_rst_meta;

    // Two stage clock domain crossing
    always_ff @(posedge clk_vga) begin
        // Stage 1
        vga_char_row_meta <= wb_char_row;
        vga_char_col_meta <= wb_char_col;
        vga_bg_color_meta <= wb_bg_color;
        vga_char_meta     <= wb_char;
        vga_rst_meta      <= wb_rst_i;
        // Stage 2
        vga_char_row      <= vga_char_row_meta;
        vga_char_col      <= vga_char_col_meta;
        vga_bg_color      <= vga_bg_color_meta;
        vga_char          <= vga_char_meta;
        vga_rst           <= vga_rst_meta;
    end

    // ==============
    // VGA Side: 25kHz
    // ===============
    logic px_en;
    logic signed [11:0] pixel_row, pixel_col;
    logic signed [15:0] xoffset, yoffset;
    logic char_loc, real_char, char_area;

    // Determine the offset between the current VGA pixel and the char upper left corner
    assign xoffset = pixel_col - {2'b0, vga_char_col}; // Zero-extend for math safety
    assign yoffset = pixel_row - {2'b0, vga_char_row};
    
    // Determine if the current pixel is inside the character region
    assign char_area = (xoffset >= 0) && (xoffset < 24) && (yoffset >= 0) && (yoffset < 20);
    // Determine that the delivered character is one of those supported
    assign real_char = (vga_char >= 8'h30) && (vga_char <= 8'h39); 

    // Character Bitmaps
    logic [48:57][0:4][0:5] char_array = 
      '{// Zero 
       {6'b011100,
        6'b100010,
        6'b100010,
        6'b100010,
        6'b011100},
        // One 
       {6'b000010,
        6'b000110,
        6'b000010,
        6'b000010,
        6'b000111},
        // Two
        {6'b001100,
         6'b010010,
         6'b000100,
         6'b001000,
         6'b011110},
         // Three
        {6'b001100,
         6'b010010,
         6'b000100,
         6'b010010,
         6'b001100},
         // Four
        {6'b010100,
         6'b010100,
         6'b011110,
         6'b000100,
         6'b000100},
         // Five
        {6'b011110,
         6'b010000,
         6'b011100,
         6'b000010,
         6'b011100},
         // Six
        {6'b001110,
         6'b010000,
         6'b011100,
         6'b010010,
         6'b001100},
         // Seven
        {6'b011111,
         6'b000010,
         6'b000100,
         6'b001000,
         6'b010000},
         // Eight
        {6'b011100,
         6'b100010,
         6'b011100,
         6'b100010,
         6'b011100},
         // Nine
        {6'b001110,
         6'b010010,
         6'b001110,
         6'b000010,
         6'b000010}};

    // VGA output logic
    always_comb begin
        VGA_Red   = '0;
        VGA_Green = '0;
        VGA_Blue  = '0;
        if (px_en) begin
            VGA_Red = vga_bg_color[11:8];
            VGA_Green = vga_bg_color[7:4];
            VGA_Blue = vga_bg_color[3:0];
        end
        if (px_en && real_char && char_area) begin
            // This code quadruples the baseline size of the characters for the display
            if (char_array[vga_char][(yoffset[5:0] >> 2)][(xoffset[6:0] >> 2)]) begin
                VGA_Red   = '1;
                VGA_Green = '1;
                VGA_Blue  = '1;
            end
        end
    end
   
    // Display Timing Generator Instantiation
    dtg dgt_instance(
      .clock        (clk_vga),
      .rst          (vga_rst), 
      .horiz_sync   (hsync),
      .vert_sync    (vsync),
      .video_on     (px_en),
      .pixel_row    (pixel_row),
      .pixel_column (pixel_col)
    );

endmodule