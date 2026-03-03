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
    output logic                wr_en,
    output logic [16:0]         wr_adr,
    output logic [7:0]          data
    
);
        
    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_color,  gpu_color_meta;
    logic [7:0] gpu_height, gpu_height_meta;
    logic       gpu_toggle, gpu_toggle_meta, gpu_toggle_d1;
    
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
