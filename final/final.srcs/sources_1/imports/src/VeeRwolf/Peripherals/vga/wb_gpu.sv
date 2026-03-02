module wb_gpu #(
    parameter int SCREEN_WIDTH = 320,
    parameter int CENTER_ROW   = 120
)(
    input  logic                wb_clk_i,
    input  logic                wb_rst_i,
    input  logic [3:0]          wb_adr_i,
    input  logic [31:0]         wb_dat_i,
    output logic [31:0]         wb_dat_o,
    input  logic                wb_we_i,
    input  logic [3:0]          wb_sel_i,
    input  logic                wb_stb_i,
    input  logic                wb_cyc_i,
    output logic                wb_ack_o,
    
    input  logic                gpu_clk,
    input  logic                gpu_rst,
    input  logic                bram_inx,

    output logic                wr_en,
    output logic [16:0]         wr_adr,
    output logic [7:0]          data,
    
    output logic                fcd 
);
        
    logic wb_bram_inx_sync;
    
    assign wb_valid_cycle = wb_cyc_i && wb_stb_i;
    assign wb_write_en    = wb_valid_cycle && wb_we_i && !wb_ack_o;
    assign wb_read_en     = wb_valid_cycle && !wb_we_i && !wb_ack_o;

    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) 
            wb_ack_o <= 1'b0;
        else          
            wb_ack_o <= wb_valid_cycle && !wb_ack_o;
    end
    
    logic [8:0]  pixel_column;
    logic [7:0]  color;
    logic [7:0]  height;
    logic wb_write_toggle;

    // New control + status
    logic        prim_mode_en;      // enables primitive engine consumption
    logic        overlay_en;        // draw primitives after raycast
    logic        cmd_overflow_sticky;
    
    // Async FIFO interface (WB side)
    logic        cmd_fifo_wr_en;
    logic [31:0] cmd_fifo_wr_data;
    logic        cmd_fifo_full;
    logic        cmd_fifo_empty_wb; // optional (WB-domain synced empty)
    
    // Async FIFO interface (GPU side)
    logic        cmd_fifo_rd_en;
    logic [31:0] cmd_fifo_rd_data;
    logic        cmd_fifo_empty;
    
    always_ff @(posedge wb_clk_i) begin
    if (wb_rst_i) begin
      pixel_column        <= '0;
      color               <= '0;
      height              <= '0;
      wb_write_toggle     <= '0;
      fcd                 <= '0;
  
      prim_mode_en        <= 1'b0;
      overlay_en          <= 1'b1;
      cmd_overflow_sticky <= 1'b0;

      cmd_fifo_wr_en      <= 1'b0;
      cmd_fifo_wr_data    <= '0;
    end
    else begin
      // default: FIFO write disabled unless we hit CMD_PUSH
      cmd_fifo_wr_en   <= 1'b0;
      cmd_fifo_wr_data <= wb_dat_i;
  
      if (wb_write_en) begin
        case (wb_adr_i)
          // 0x04: existing raycast column packet
          4'h1: begin
            pixel_column    <= wb_dat_i[8:0];
            color           <= wb_dat_i[16:9];
            height          <= wb_dat_i[24:17];
            wb_write_toggle <= ~wb_write_toggle;
          end
  
          // 0x08: existing frame calc done
          4'h2: begin
            fcd <= wb_dat_i[0];
          end
  
          // 0x10: new control reg
          // [0] prim_mode_en
          // [1] clear_fifo (pulse)
          // [2] clear_error (pulse)
          // [3] overlay_en
          4'h4: begin
            prim_mode_en <= wb_dat_i[0];
            overlay_en   <= wb_dat_i[3];
  
            if (wb_dat_i[2]) begin
              cmd_overflow_sticky <= 1'b0;
            end
            // clear_fifo is handled by FIFO reset/flush logic (see note below)
          end
  
          // 0x14: new command push (to async FIFO)
          4'h5: begin
            if (!cmd_fifo_full) begin
              cmd_fifo_wr_en   <= 1'b1;
              cmd_fifo_wr_data <= wb_dat_i;
            end else begin
              cmd_overflow_sticky <= 1'b1; // sticky overflow flag
            end
          end
  
          default: begin end
        endcase
      end
    end
   end

   always_ff @(posedge wb_clk_i) begin
     if (wb_rst_i) begin
       wb_dat_o <= '0;
     end
     else if (wb_read_en) begin
       case (wb_adr_i)
         // 0x00: existing VGA frame buffer index
         4'h0: wb_dat_o <= {31'b0, wb_bram_inx_sync};

         // 0x0C: GPU_STATUS
         // [0] busy (you can drive later from GPU domain + sync)
         // [1] cmd_fifo_full
         // [2] cmd_fifo_empty (optional: WB-domain view; see note)
         // [3] prim_mode_en
         // [4] overlay_en
         // [5] overflow_sticky
         4'h3: wb_dat_o <= {
           26'b0,
           cmd_overflow_sticky,  // [5]
           overlay_en,           // [4]
           prim_mode_en,         // [3]
           cmd_fifo_empty_wb,    // [2] (optional)
           cmd_fifo_full,        // [1]
           1'b0                  // [0] busy (stub for now)
         };
   
         default: wb_dat_o <= '0;
       endcase
     end
     else wb_dat_o <= '0;
   end 

    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_color,  gpu_color_meta;
    logic [7:0] gpu_height, gpu_height_meta;
    logic       gpu_toggle, gpu_toggle_meta, gpu_toggle_d1;
    
    always_ff @(posedge gpu_clk) begin
        gpu_column_meta <= pixel_column;
        gpu_color_meta  <= color;
        gpu_height_meta <= height;
        gpu_toggle_meta <= wb_write_toggle;
        
        gpu_column <= gpu_column_meta;
        gpu_color  <= gpu_color_meta;
        gpu_height <= gpu_height_meta;
        gpu_toggle <= gpu_toggle_meta;
        
        gpu_toggle_d1 <= gpu_toggle;
    end  
    
    logic new_data_pulse;
    assign new_data_pulse = gpu_toggle ^ gpu_toggle_d1;

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
    
    logic wb_bram_inx_meta;

    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_bram_inx_meta <= 1'b0;
            wb_bram_inx_sync <= 1'b0;
        end else begin
            wb_bram_inx_meta <= bram_inx;
            wb_bram_inx_sync <= wb_bram_inx_meta;
        end
    end

    logic cmd_fifo_empty_meta, cmd_fifo_empty_sync;

    always_ff @(posedge wb_clk_i) begin
      if (wb_rst_i) begin
        cmd_fifo_empty_meta <= 1'b1;
        cmd_fifo_empty_sync <= 1'b1;
      end else begin
        cmd_fifo_empty_meta <= cmd_fifo_empty;
        cmd_fifo_empty_sync <= cmd_fifo_empty_meta;
      end
    end
    
    assign cmd_fifo_empty_wb = cmd_fifo_empty_sync;
    
    typedef enum logic {IDLE, DRAW} state_t;
    state_t current_state;

    logic [7:0] y_cnt; 
    logic [7:0] wall_top, wall_bottom;

    always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
            current_state <= IDLE;
            wr_en         <= 1'b0;
            y_cnt         <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    wr_en <= 1'b0;
                    if (new_data_pulse) begin
                        y_cnt         <= 0;
                        wall_top      <= (CENTER_ROW > (gpu_height >> 1)) ? (CENTER_ROW - (gpu_height >> 1)) : 0;
                        wall_bottom   <= (CENTER_ROW + (gpu_height >> 1));
                        current_state <= DRAW;
                    end
                end

                DRAW: begin
                    wr_en  <= 1'b1;
                    wr_adr <= (y_cnt * SCREEN_WIDTH) + gpu_column;
                    
                    if (y_cnt < wall_top)
                        data <= 8'h33; 
                    else if (y_cnt > wall_bottom)
                        data <= 8'h77; 
                    else
                        data <= gpu_color; 

                    if (y_cnt == 239) begin
                        current_state <= IDLE;
                    end else begin
                        y_cnt <= y_cnt + 1;
                    end
                end
            endcase
        end
    end

    async_fifo #(
      .WIDTH(32),
      .DEPTH(64)           // 32 or 64 is plenty to start
    ) u_cmd_fifo (
      // write clock domain (Wishbone)
      .wr_clk  (wb_clk_i),
      .wr_rst  (wb_rst_i),
      .wr_en   (cmd_fifo_wr_en),
      .wr_data (cmd_fifo_wr_data),
      .wr_full (cmd_fifo_full),
    
      // read clock domain (GPU)
      .rd_clk  (gpu_clk),
      .rd_rst  (gpu_rst),          // if you have one; otherwise use wb_rst_i synced or wb_rst_i if shared
      .rd_en   (cmd_fifo_rd_en),
      .rd_data (cmd_fifo_rd_data),
      .rd_empty(cmd_fifo_empty)
    );

    // Simple command latch
    logic        cmd_valid;
    logic [31:0] cmd_word;
    
    // Optional: track opcode
    logic [3:0]  cmd_opcode;

    logic sample_fifo_data;
    
    // If you plan to do multi-word commands (LINE_A/LINE_B), add a small staging state
    typedef enum logic [1:0] {CMD_IDLE, CMD_POP, CMD_LATCH} cmd_state_t;
    cmd_state_t cmd_state;

    assign sample_fifo_data = prim_mode_en_gpu && !cmd_fifo_empty;
    assign cmd_fifo_rd_en = sample_fifo_data && (cmd_state == CMD_IDLE); // request pop

    always_ff @(posedge gpu_clk) begin
       if (gpu_rst) begin
         cmd_state      <= CMD_IDLE;
         cmd_valid      <= 1'b0;
         cmd_word       <= 32'b0;
         cmd_opcode     <= 4'h0;
       end else begin
         // defaults
         cmd_valid      <= 1'b0;
     
         case (cmd_state)
           CMD_IDLE: begin
             // Only drain when primitive mode enabled AND fifo has data
             // prim_mode_en is currently WB-domain; you should sync it into gpu_clk domain first.
             if (sample_fifo_data) begin
               cmd_state      <= CMD_LATCH; // latch next cycle
             end
           end
     
           CMD_LATCH: begin
             // rd_data is updated on the previous cycle's pop
             cmd_word   <= cmd_fifo_rd_data;
             cmd_opcode <= cmd_fifo_rd_data[31:28];
             cmd_valid  <= 1'b1;
     
             // Go back to idle; later this will feed a command decoder
             cmd_state <= CMD_IDLE;
           end
     
           default: cmd_state <= CMD_IDLE;
         endcase
       end
     end

     always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
          // debug counters (optional)
        end else if (cmd_valid) begin
          unique case (cmd_opcode)
            4'h1: begin
              // LINE_A (example)
              // later: latch x0,y0,x1 and wait for LINE_B
            end
            4'h2: begin
              // LINE_B
            end
            default: begin
              // ignore for now
            end
          endcase
        end
      end 

endmodule
