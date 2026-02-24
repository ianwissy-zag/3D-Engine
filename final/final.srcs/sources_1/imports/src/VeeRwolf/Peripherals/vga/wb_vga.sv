module wb_vga #(
    parameter WIDTH = 640, 
    parameter HEIGHT = 480
)(
    // Bram ports
    output logic                    rd_en,
    output logic [16:0]             rd_adr,
    input  logic [7:0]              data,

    // VGA Ports 
    input  logic                    clk_vga,    // Pixel Clock
    input  logic                    rst,
    output logic [3:0]              VGA_Red,
    output logic [3:0]              VGA_Green,
    output logic [3:0]              VGA_Blue,
    output logic                    vsync,
    output logic                    hsync
);

    // DTG wires
    logic        hsync_dtg;
    logic        vsync_dtg;
    logic        px_en_dtg;
    logic [10:0] pixel_row;
    logic [10:0] pixel_col;

    // DTG init
    dtg dgt_instance(
      .clock        (clk_vga),
      .rst          (rst), 
      .horiz_sync   (hsync_dtg),
      .vert_sync    (vsync_dtg),
      .video_on     (px_en_dtg),
      .pixel_row    (pixel_row),
      .pixel_column (pixel_col)
    );

    // Hardware right shift for pixel doubling 
    logic [8:0] scaled_x; 
    logic [7:0] scaled_y; 
    assign scaled_x = pixel_col[9:1]; 
    assign scaled_y = pixel_row[8:1]; 

    // Address calculations
    always_ff @(posedge clk_vga or posedge rst) begin
        if (rst) begin
            rd_adr <= 17'd0;
            rd_en  <= 1'b0;
        end else begin
            // It is probably not neccessary to be this efficent 
            rd_adr <= ({9'd0, scaled_y} << 8) + ({9'd0, scaled_y} << 6) + {8'd0, scaled_x};
            rd_en  <= px_en_dtg;
        end
    end

    // You have to delay data from the dtg or everything is offset one pixel
    logic hsync_d1, hsync_d2;
    logic vsync_d1, vsync_d2;
    logic px_en_d1, px_en_d2;

    always_ff @(posedge clk_vga or posedge rst) begin
        if (rst) begin
            {hsync_d2, hsync_d1} <= 2'b0;
            {vsync_d2, vsync_d1} <= 2'b0;
            {px_en_d2, px_en_d1} <= 2'b0;
        end else begin
            hsync_d1 <= hsync_dtg;
            hsync_d2 <= hsync_d1;
            
            vsync_d1 <= vsync_dtg;
            vsync_d2 <= vsync_d1;
            
            px_en_d1 <= px_en_dtg;
            px_en_d2 <= px_en_d1;
        end
    end

    // Output delayed signal
    assign hsync = hsync_d2;
    assign vsync = vsync_d2;

    // Map 8 bit to 12 bit (we may want to do 12 bit internally)
    logic [3:0] red_mapped;
    logic [3:0] green_mapped;
    logic [3:0] blue_mapped;

    assign red_mapped   = {data[7:5], data[5]};
    assign green_mapped = {data[4:2], data[2]};
    assign blue_mapped  = {data[1:0], data[1:0]};

    // Output to VGA
    always_comb begin
        if (px_en_d2) begin
            VGA_Red   = red_mapped;
            VGA_Green = green_mapped;
            VGA_Blue  = blue_mapped;
        end else begin
            VGA_Red   = 4'd0;
            VGA_Green = 4'd0;
            VGA_Blue  = 4'd0;
        end
    end

endmodule