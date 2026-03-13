module wb_gpu #(
    parameter int SCREEN_WIDTH = 320,
    parameter int CENTER_ROW   = 120
)(
    input  logic                gpu_clk,
    input  logic                gpu_rst,
    input  logic [8:0]          pixel_column,
    input  logic [7:0]          color,
    input  logic [7:0]          height,
    input  logic                write_toggle,
    input  logic                overlay_en,
    input  logic                prim_mode_en,
    input  logic                cmd_fifo_empty,
    input  logic [31:0]         cmd_fifo_rd_data,

    output logic                cmd_fifo_rd_en,
    output logic                busy,
    output logic                wr_en,
    output logic [16:0]         wr_adr,
    output logic [7:0]          data
);
    
    // Z-table storage: 1D array storing wall heights per column (320 entries)
    logic [7:0] z_table [0:SCREEN_WIDTH-1];
    // Pipeline registers to align Z-data with the triangle rasterizer's d2 stage
    logic [7:0] z_val_d1, z_val_d2;

    logic        rc_wr_en;
    logic [16:0] rc_wr_adr;
    logic [7:0]  rc_wr_data;
    
    logic        tri_wr_en;
    logic [16:0] tri_wr_adr;
    logic [7:0]  tri_wr_data;

    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_color,  gpu_color_meta;
    logic [7:0] gpu_height, gpu_height_meta;
    logic        gpu_toggle, gpu_toggle_meta, gpu_toggle_d1;
    
    always_ff @(posedge gpu_clk) begin
        gpu_column_meta <= pixel_column;
        gpu_color_meta  <= color;
        gpu_height_meta <= height;
        gpu_toggle_meta <= write_toggle;
        
        gpu_column <= gpu_column_meta;
        gpu_color  <= gpu_color_meta;
        gpu_height <= gpu_height_meta;
        gpu_toggle <= gpu_toggle_meta;
        
        gpu_toggle_d1 <= gpu_toggle;
    end  
    
    logic new_data_pulse;
    assign new_data_pulse = gpu_toggle ^ gpu_toggle_d1;

    // Write to Z-table: update height for the current column when raycaster finishes
    always_ff @(posedge gpu_clk) begin
        if (new_data_pulse) begin
            z_table[gpu_column] <= gpu_height;
        end
    end

    logic prim_mode_en_meta, prim_mode_en_gpu;
    logic overlay_en_meta,   overlay_en_gpu;
    
    always_ff @(posedge gpu_clk) begin
      if (gpu_rst) begin
        prim_mode_en_meta <= 1'b0;
        prim_mode_en_gpu  <= 1'b0;
        overlay_en_meta   <= 1'b1;
        overlay_en_gpu    <= 1'b1;
      end else begin
        prim_mode_en_meta <= prim_mode_en;
        prim_mode_en_gpu  <= prim_mode_en_meta;
        overlay_en_meta   <= overlay_en;
        overlay_en_gpu    <= overlay_en_meta;
      end
    end
    
    typedef enum logic {IDLE, DRAW} state_t;
    state_t current_state;

    logic [7:0] y_cnt; 
    logic [7:0] wall_top, wall_bottom;

    always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
            current_state <= IDLE;
            rc_wr_en          <= 1'b0;
            y_cnt          <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    rc_wr_en <= 1'b0;
                    if (new_data_pulse) begin
                        y_cnt          <= 0;
                        wall_top      <= (CENTER_ROW > (gpu_height >> 1)) ? (CENTER_ROW - (gpu_height >> 1)) : 0;
                        wall_bottom   <= (CENTER_ROW + (gpu_height >> 1));
                        current_state <= DRAW;
                    end
                end

                DRAW: begin
                    rc_wr_en  <= 1'b1;
                    rc_wr_adr <= (y_cnt * SCREEN_WIDTH) + gpu_column;
                    
                    if (y_cnt < wall_top)
                        rc_wr_data <= 8'h33; 
                    else if (y_cnt > wall_bottom)
                        rc_wr_data <= 8'h77; 
                    else
                        rc_wr_data <= gpu_color; 

                    if (y_cnt == 239) begin
                        current_state <= IDLE;
                    end else begin
                        y_cnt <= y_cnt + 1;
                    end
                end
            endcase
        end
    end

    // Simple command latch
    logic        cmd_valid;
    logic [31:0] cmd_word;
    
    // Optional: track opcode
    logic [1:0]  cmd_opcode;

    logic tri_engine_idle;
    logic tri_start_pending;
    logic sample_fifo_data;
    
    // If you plan to do multi-word commands (LINE_A/LINE_B), add a small staging state
    typedef enum logic [1:0] {CMD_IDLE, CMD_POP, CMD_LATCH} cmd_state_t;
    cmd_state_t cmd_state;
    typedef enum logic [1:0] {T_IDLE, T_SETUP0, T_SETUP1, T_DRAW} tri_state_t;
    tri_state_t tri_state;

    assign tri_engine_idle = (tri_state == T_IDLE) && !tri_start_pending;
    assign sample_fifo_data = prim_mode_en_gpu && !cmd_fifo_empty && tri_engine_idle;
    assign cmd_fifo_rd_en = sample_fifo_data && (cmd_state == CMD_IDLE); // request pop

    always_ff @(posedge gpu_clk) begin
       if (gpu_rst) begin
         cmd_state      <= CMD_IDLE;
         cmd_valid      <= 1'b0;
         cmd_word       <= 32'b0;
         cmd_opcode     <= 2'h0;
       end else begin
         // defaults
         cmd_valid      <= 1'b0;
     
         case (cmd_state)
           CMD_IDLE: begin
             // Only drain when primitive mode enabled AND fifo has data
             if (sample_fifo_data) begin
               cmd_state      <= CMD_LATCH; // latch next cycle
             end
           end
     
           CMD_LATCH: begin
             // rd_data is updated on the previous cycle's pop
             cmd_word   <= cmd_fifo_rd_data;
             cmd_opcode <= cmd_fifo_rd_data[31:30];
             cmd_valid  <= 1'b1;
     
             // Go back to idle; later this will feed a command decoder
             cmd_state <= CMD_IDLE;
           end
     
           default: cmd_state <= CMD_IDLE;
         endcase
       end
     end

    // Triangle staging
    logic have_v0, have_v1, have_v2;
    
    logic signed [10:0] tri_x0, tri_x1, tri_x2;
    logic signed [9:0]  tri_y0, tri_y1, tri_y2;
    logic [7:0] tri_color;
    logic [7:0] tri_height; // Dynamic height latched per triangle
    
    logic tri_start;   // pulse to start raster FSM

    always_ff @(posedge gpu_clk) begin
       if (gpu_rst) begin
         have_v0   <= 1'b0;
         have_v1   <= 1'b0;
         have_v2   <= 1'b0;
         tri_x0    <= '0; tri_y0 <= '0;
         tri_x1    <= '0; tri_y1 <= '0;
         tri_x2    <= '0; tri_y2 <= '0;
         tri_color <= '0;
         tri_height <= '0;
         tri_start <= 1'b0;
       end else begin
         tri_start <= 1'b0;
     
         if (cmd_valid) begin
           unique case (cmd_opcode)
             2'b00: begin // TRI_V0
               tri_x0  <= $signed(cmd_word[29:19]);
               tri_y0  <= $signed(cmd_word[18:9]);
               have_v0 <= 1'b1;
             end
     
             2'b01: begin // TRI_V1
               tri_x1  <= $signed(cmd_word[29:19]);
               tri_y1  <= $signed(cmd_word[18:9]);
               have_v1 <= 1'b1;
             end
     
             2'b10: begin // TRI_V2
               tri_x2  <= $signed(cmd_word[29:19]);
               tri_y2  <= $signed(cmd_word[18:9]);
               have_v2 <= 1'b1;
             end
     
             2'b11: begin // TRI_SUBMIT
               if (have_v0 && have_v1 && have_v2) begin
                 tri_color  <= cmd_word[29:22];
                 // Latch height from the next bits in the command word
                 tri_height <= cmd_word[21:14]; 
                 tri_start  <= 1'b1;
     
                 // consume vertices for next triangle
                 have_v0 <= 1'b0;
                 have_v1 <= 1'b0;
                 have_v2 <= 1'b0;
               end
             end
     
             default: begin end
           endcase
         end
       end
     end 

    logic signed [10:0] min_x, max_x, x_cur;
    logic signed [9:0] min_y, max_y, y_cur;
    
    always_ff @(posedge gpu_clk) begin
      if (gpu_rst) tri_start_pending <= 1'b0;
      else if (tri_start) tri_start_pending <= 1'b1;
      else if (tri_state == T_SETUP0) tri_start_pending <= 1'b0;
    end

    // Signed vertices latched for setup stages
    logic signed [10:0] x0s, x1s, x2s;
    logic signed [9:0]  y0s, y1s, y2s;
    
    // BBox origin in signed form
    logic signed [10:0] mxs;
    logic signed [9:0]  mys;
    
    // Edge deltas
    logic signed [10:0] dx01, dx12, dx20;
    logic signed [9:0]  dy01, dy12, dy20;
    
    // Edge step increments (incremental raster)
    logic signed [9:0]  e01_stepX, e12_stepX, e20_stepX;  // -dy
    logic signed [10:0] e01_stepY, e12_stepY, e20_stepY;  // +dx
    
    // Edge values at current pixel and at row start
    logic signed [23:0] e01, e12, e20;
    logic signed [23:0] e01_row, e12_row, e20_row;
    
    // Address helper (row_base = y*320)
    logic [16:0] row_base;

    logic inside_tri_reg;

    logic e01_pos, e01_neg, e12_pos, e12_neg, e20_pos, e20_neg;

    always_ff @(posedge gpu_clk) begin
      if (gpu_rst) begin
        e01_pos <= 1'b0; e01_neg <= 1'b0;
        e12_pos <= 1'b0; e12_neg <= 1'b0;
        e20_pos <= 1'b0; e20_neg <= 1'b0;
      end else if (tri_state == T_DRAW) begin
        e01_pos <= (e01 >= 0);
        e01_neg <= (e01 <= 0);
        e12_pos <= (e12 >= 0);
        e12_neg <= (e12 <= 0);
        e20_pos <= (e20 >= 0);
        e20_neg <= (e20 <= 0);
      end
    end

    always_ff @(posedge gpu_clk) begin
      if (gpu_rst) begin
        inside_tri_reg <= 1'b0;
      end else if (tri_state == T_DRAW) begin
        inside_tri_reg <= (e01_pos && e12_pos && e20_pos) ||
                          (e01_neg && e12_neg && e20_neg);
      end else begin
        inside_tri_reg <= 1'b0;
      end
    end

    logic signed [10:0] x_d1, x_d2;
    logic signed [9:0] y_d1, y_d2;
    logic draw_valid_d1, draw_valid_d2;
    
    always_ff @(posedge gpu_clk) begin
      if (gpu_rst) begin
        x_d1 <= '0;
        x_d2 <= '0;
        y_d1 <= '0;
        y_d2 <= '0;
        draw_valid_d1 <= 1'b0;
        draw_valid_d2 <= 1'b0;
        z_val_d1 <= 8'h0; 
        z_val_d2 <= 8'h0;
      end else begin
        x_d1 <= x_cur;
        x_d2 <= x_d1;
        y_d1 <= y_cur;
        y_d2 <= y_d1;
        draw_valid_d1 <= (tri_state == T_DRAW);
        draw_valid_d2 <= draw_valid_d1;

        // BRAM read latency: request at cycle 0, data ready at cycle 1
        if (x_cur >= 0 && x_cur < SCREEN_WIDTH)
            z_val_d1 <= z_table[x_cur];
        else
            z_val_d1 <= 8'h00; 

        // Delay Z data one more cycle to match coordinate d2 stage
        z_val_d2 <= z_val_d1;
      end
    end

    logic [16:0] row_base_d1, row_base_d2;

    always_ff @(posedge gpu_clk) begin
      if (gpu_rst) begin
        row_base_d1 <= '0;
        row_base_d2 <= '0;
      end
      else begin
        row_base_d1 <= row_base;
        row_base_d2 <= row_base_d1;
      end
    end
    

    always_ff @(posedge gpu_clk) begin
       if (gpu_rst) begin
         tri_state <= T_IDLE;
         x_cur     <= '0;
         y_cur     <= '0;
         min_x     <= '0;
         max_x     <= '0;
         min_y     <= '0;
         max_y     <= '0;
     
         // edge regs
         e01 <= '0; e12 <= '0; e20 <= '0;
         e01_row <= '0; e12_row <= '0; e20_row <= '0;
     
         // steps/deltas
         dx01 <= '0; dx12 <= '0; dx20 <= '0;
         dy01 <= '0; dy12 <= '0; dy20 <= '0;
         e01_stepX <= '0; e12_stepX <= '0; e20_stepX <= '0;
         e01_stepY <= '0; e12_stepY <= '0; e20_stepY <= '0;
     
         // signed vertex latches
         x0s <= '0; x1s <= '0; x2s <= '0;
         y0s <= '0; y1s <= '0; y2s <= '0;
         mxs <= '0; mys <= '0;
     
         row_base <= '0;
       end else begin
         case (tri_state)
           T_IDLE: begin
             if (tri_start_pending) begin
               tri_state <= T_SETUP0;
             end
           end
     
           T_SETUP0: begin
             min_x <= min3_11(tri_x0, tri_x1, tri_x2);
             max_x <= max3_11(tri_x0, tri_x1, tri_x2);
             min_y <= min3_10(tri_y0, tri_y1, tri_y2);
             max_y <= max3_10(tri_y0, tri_y1, tri_y2);
     
             x_cur <= min3_11(tri_x0, tri_x1, tri_x2);
             y_cur <= min3_10(tri_y0, tri_y1, tri_y2);
     
             x0s <= tri_x0; x1s <= tri_x1; x2s <= tri_x2;
             y0s <= tri_y0; y1s <= tri_y1; y2s <= tri_y2;
     
             mxs <= min3_11(tri_x0, tri_x1, tri_x2);
             mys <= min3_10(tri_y0, tri_y1, tri_y2);
     
             dx01 <= tri_x1 - tri_x0; dy01 <= tri_y1 - tri_y0;
             dx12 <= tri_x2 - tri_x1; dy12 <= tri_y2 - tri_y1;
             dx20 <= tri_x0 - tri_x2; dy20 <= tri_y0 - tri_y2;
     
             e01_stepX <= -(tri_y1 - tri_y0); e01_stepY <= (tri_x1 - tri_x0);
             e12_stepX <= -(tri_y2 - tri_y1); e12_stepY <= (tri_x2 - tri_x1);
             e20_stepX <= -(tri_y0 - tri_y2); e20_stepY <= (tri_x0 - tri_x2);
     
             tri_state <= T_SETUP1;
           end
     
           T_SETUP1: begin
             e01_row <= ( (mys - y0s) * dx01 ) - ( (mxs - x0s) * dy01 );
             e12_row <= ( (mys - y1s) * dx12 ) - ( (mxs - x1s) * dy12 );
             e20_row <= ( (mys - y2s) * dx20 ) - ( (mxs - x2s) * dy20 );
     
             e01 <= ( (mys - y0s) * dx01 ) - ( (mxs - x0s) * dy01 );
             e12 <= ( (mys - y1s) * dx12 ) - ( (mxs - x1s) * dy12 );
             e20 <= ( (mys - y2s) * dx20 ) - ( (mxs - x2s) * dy20 );
     
             row_base <= ({7'b0, min3_10(tri_y0, tri_y1, tri_y2)} << 8) +
                         ({7'b0, min3_10(tri_y0, tri_y1, tri_y2)} << 6);
     
             tri_state <= T_DRAW;
           end
     
           T_DRAW: begin
             if (x_cur == max_x) begin
               x_cur <= min_x;
               if (y_cur == max_y) begin
                 tri_state <= T_IDLE;
               end else begin
                 y_cur <= y_cur + 1;
                 e01_row <= e01_row + e01_stepY;
                 e12_row <= e12_row + e12_stepY;
                 e20_row <= e20_row + e20_stepY;
                 e01 <= e01_row + e01_stepY;
                 e12 <= e12_row + e12_stepY;
                 e20 <= e20_row + e20_stepY;
                 row_base <= row_base + 17'd320;
               end
             end else begin
               x_cur <= x_cur + 1;
               e01 <= e01 + e01_stepX;
               e12 <= e12 + e12_stepX;
               e20 <= e20 + e20_stepX;
             end
           end
     
           default: tri_state <= T_IDLE;
         endcase
       end
     end

    always_comb begin
       tri_wr_en   = 1'b0;
       tri_wr_adr  = '0;
       tri_wr_data = tri_color;
     
       if (draw_valid_d2) begin
         if (x_d2 >= 0 && x_d2 < $signed({2'b0, SCREEN_WIDTH[8:0]}) && y_d2 >= 0 && y_d2 < 240) begin
           if (inside_tri_reg) begin
             // Dynamic Depth Test: Compare latched tri_height against current Z-table value
             if (tri_height >= z_val_d2) begin
                tri_wr_en   = 1'b1;
                tri_wr_adr  = row_base_d2 + 17'(x_d2);
                tri_wr_data = tri_color;
             end
           end
         end
       end
     end

    always_comb begin
       wr_en  = rc_wr_en;
       wr_adr = rc_wr_adr;
       data   = rc_wr_data;
     
       if (overlay_en_gpu && tri_wr_en) begin
         wr_en  = tri_wr_en;
         wr_adr = tri_wr_adr;
         data   = tri_wr_data;
       end
   end

   assign busy = (current_state != IDLE) || (tri_state != T_IDLE) ||
                  have_v0 || have_v1 || have_v2 || tri_start_pending;

// Functions
function automatic signed [10:0] min3_11(input signed [10:0] a,b,c);
  min3_11 = (a<b) ? ((a<c)?a:c) : ((b<c)?b:c);
endfunction

function automatic signed [10:0] max3_11(input signed [10:0] a,b,c);
  max3_11 = (a>b) ? ((a>c)?a:c) : ((b>c)?b:c);
endfunction

function automatic signed [9:0] min3_10(input signed [9:0] a,b,c);
  min3_10 = (a<b) ? ((a<c)?a:c) : ((b<c)?b:c);
endfunction

function automatic signed [9:0] max3_10(input signed [9:0] a,b,c);
  max3_10 = (a>b) ? ((a>c)?a:c) : ((b>c)?b:c);
endfunction 

endmodule
