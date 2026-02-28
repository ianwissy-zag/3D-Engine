module vga #(
    parameter WIDTH = 640, 
    parameter HEIGHT = 480
)(
    output logic                    rd_en,
    output logic [16:0]             rd_adr,
    output logic                    bram_inx,
    input  logic [7:0]              data,

    input  logic                    clk_vga,    
    input  logic                    rst,
    output logic [3:0]              VGA_Red,
    output logic [3:0]              VGA_Green,
    output logic [3:0]              VGA_Blue,
    output logic                    vsync,
    output logic                    hsync,
    
    input  logic                    fcd 
);

    logic        hsync_dtg;
    logic        vsync_dtg;
    logic        px_en_dtg;
    logic [10:0] pixel_row;
    logic [10:0] pixel_col;

    dtg dgt_instance(
      .clock        (clk_vga),
      .rst          (rst), 
      .horiz_sync   (hsync_dtg),
      .vert_sync    (vsync_dtg),
      .video_on     (px_en_dtg),
      .pixel_row    (pixel_row),
      .pixel_column (pixel_col)
    );

    logic [8:0] scaled_x; 
    logic [7:0] scaled_y; 
    assign scaled_x = pixel_col[9:1]; 
    assign scaled_y = pixel_row[8:1]; 
    
    logic fcd_meta, fcd_sync;
    
    always_ff @(posedge clk_vga) begin
        if (rst) begin
            fcd_meta <= 1'b0;
            fcd_sync <= 1'b0;
        end else begin
            fcd_meta <= fcd;
            fcd_sync <= fcd_meta;
        end
    end
    
    always_ff @(posedge clk_vga) begin
        if (rst) begin
            bram_inx <= 0;
        end else if (pixel_col == 0 && pixel_row == 480 && fcd_sync) begin
            bram_inx <= ~bram_inx;
        end
    end
    
    always_ff @(posedge clk_vga) begin
        if (rst) begin
            rd_adr <= 17'd0;
            rd_en  <= 1'b0;
        end else begin
            rd_adr <= ({9'd0, scaled_y} << 8) + ({9'd0, scaled_y} << 6) + {8'd0, scaled_x};
            rd_en  <= px_en_dtg;
        end
    end

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

    assign hsync = hsync_d2;
    assign vsync = vsync_d2;

    logic [3:0] red_mapped;
    logic [3:0] green_mapped;
    logic [3:0] blue_mapped;

    assign red_mapped   = {data[7:5], data[5]};
    assign green_mapped = {data[4:2], data[2]};
    assign blue_mapped  = {data[1:0], data[1:0]};

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