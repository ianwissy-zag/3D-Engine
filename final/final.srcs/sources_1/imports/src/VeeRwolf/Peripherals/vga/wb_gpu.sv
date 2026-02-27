module wb_gpu #(
    parameter int SCREEN_WIDTH = 320,
    parameter int CENTER_ROW   = 120
)(
    // Wishbone interconnect (Slave Interface)
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
    
    // 100 MHz Clock
    input  logic                gpu_clk,
    input  logic                gpu_rst,
    input  logic                bram_inx,

    // VGA Ports 
    output logic                wr_en,
    output logic [16:0]         wr_adr,
    output logic [7:0]          data
);

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
    
    // Input logic from wishbone
    logic [8:0]  pixel_column;
    logic [7:0]  color;
    logic [7:0]  height;
    
    // New write signal (flips on new write)
    logic wb_write_toggle;
    
    // Write
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            pixel_column    <= '0;
            color           <= '0;
            height          <= '0;
            wb_write_toggle <= '0;
        end 
        else if (wb_write_en) begin
            pixel_column    <= wb_dat_i[8:0];
            color           <= wb_dat_i[16:9];
            height          <= wb_dat_i[24:17];
            wb_write_toggle <= ~wb_write_toggle; 
        end
    end

    // Read
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_dat_o <= '0;
        end else if (wb_read_en) begin
            case (wb_adr_i)
                4'h0:    wb_dat_o <= {31'b0, wb_bram_inx_sync};
                default: wb_dat_o <= '0;
            endcase 
        end
        else wb_dat_o <= '0;
    end
    
    // ==============================================================
    //    Clock Domain Crossings
    // ====================================
    
    //------------ Wishbone to GPU ----------------
    
    // Double flip flop to cross clock domain
    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_color,  gpu_color_meta;
    logic [7:0] gpu_height, gpu_height_meta;
    logic       gpu_toggle, gpu_toggle_meta, gpu_toggle_d1;
    
    // Shifting 
    always_ff @(posedge gpu_clk) begin
        // Stage 1
        gpu_column_meta <= pixel_column;
        gpu_color_meta  <= color;
        gpu_height_meta <= height;
        gpu_toggle_meta <= wb_write_toggle;
        
        // Stage 2
        gpu_column <= gpu_column_meta;
        gpu_color  <= gpu_color_meta;
        gpu_height <= gpu_height_meta;
        gpu_toggle <= gpu_toggle_meta;
        
        // Stage 3
        gpu_toggle_d1 <= gpu_toggle;
    end  
    
    logic new_data_pulse;
    assign new_data_pulse = gpu_toggle ^ gpu_toggle_d1;
    
    // ------------------ GPU to Wishbone ---------------
    
    logic wb_bram_inx_meta;
    logic wb_bram_inx_sync;

    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_bram_inx_meta <= 1'b0;
            wb_bram_inx_sync <= 1'b0;
        end else begin
            wb_bram_inx_meta <= bram_inx;
            wb_bram_inx_sync <= wb_bram_inx_meta;
        end
    end
    
    // ============================================
    // GPU (100 MHz)
    
   // FSM States
    typedef enum logic {IDLE, DRAW} state_t;
    state_t current_state;

    logic [7:0] y_cnt; // Vertical counter (0-239)
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
                        // Calculate boundaries once per column
                        wall_top      <= (CENTER_ROW > (gpu_height >> 1)) ? (CENTER_ROW - (gpu_height >> 1)) : 0;
                        wall_bottom   <= (CENTER_ROW + (gpu_height >> 1));
                        current_state <= DRAW;
                    end
                end

                DRAW: begin
                    wr_en  <= 1'b1;
                    wr_adr <= (y_cnt * SCREEN_WIDTH) + gpu_column;
                    
                    // Determine pixel color based on vertical position
                    if (y_cnt < wall_top)
                        data <= 8'h33; // Ceiling Color
                    else if (y_cnt > wall_bottom)
                        data <= 8'h77; // Floor Color
                    else
                        data <= gpu_color; // Wall

                    // Increment and check bounds
                    if (y_cnt == 239) begin
                        current_state <= IDLE;
                    end else begin
                        y_cnt <= y_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule