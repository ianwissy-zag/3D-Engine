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
        
    logic wb_valid_cycle, wb_write_en, wb_read_en;
    logic wb_bram_inx_sync, wb_bram_inx_meta;
    
    assign wb_valid_cycle = wb_cyc_i && wb_stb_i;
    assign wb_write_en    = wb_valid_cycle && wb_we_i && !wb_ack_o;
    assign wb_read_en     = wb_valid_cycle && !wb_we_i && !wb_ack_o;

    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) wb_ack_o <= 1'b0;
        else          wb_ack_o <= wb_valid_cycle && !wb_ack_o;
    end
    
    // ---------------------------------------------------------
    // 1. WIDENED HEIGHT REGISTERS (10-bit)
    // ---------------------------------------------------------
    logic [8:0] pixel_column;
    logic [7:0] texX; 
    logic [9:0] height;         // Updated to 10 bits
    logic       wb_write_toggle;
    
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            pixel_column    <= '0;
            texX            <= '0;
            height          <= '0;
            wb_write_toggle <= '0;
            fcd             <= '0;
        end else if (wb_write_en) begin
            case (wb_adr_i) 
                4'h1: begin
                    pixel_column    <= wb_dat_i[8:0];
                    texX            <= wb_dat_i[16:9];
                    height          <= wb_dat_i[26:17]; // Now grabs 10 bits!
                    wb_write_toggle <= ~wb_write_toggle; 
                end
                4'h2: fcd <= wb_dat_i[0];
            endcase
        end
    end

    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) wb_dat_o <= '0;
        else if (wb_read_en) begin
            case (wb_adr_i)
                4'h0:    wb_dat_o <= {31'b0, wb_bram_inx_sync};
                default: wb_dat_o <= '0;
            endcase 
        end else wb_dat_o <= '0;
    end
    
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_bram_inx_meta <= 1'b0;
            wb_bram_inx_sync <= 1'b0;
        end else begin
            wb_bram_inx_meta <= bram_inx;
            wb_bram_inx_sync <= wb_bram_inx_meta;
        end
    end

    // ---------------------------------------------------------
    // 2. WIDENED GPU DOMAIN REGISTERS (10-bit)
    // ---------------------------------------------------------
    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_texX,   gpu_texX_meta;
    logic [9:0] gpu_height, gpu_height_meta; // Updated to 10 bits
    logic       gpu_toggle, gpu_toggle_meta, gpu_toggle_d1;
    logic       new_data_pulse;
    
    always_ff @(posedge gpu_clk) begin
        gpu_column_meta <= pixel_column;
        gpu_texX_meta   <= texX;
        gpu_height_meta <= height;
        gpu_toggle_meta <= wb_write_toggle;
        
        gpu_column    <= gpu_column_meta;
        gpu_texX      <= gpu_texX_meta;
        gpu_height    <= gpu_height_meta;
        gpu_toggle    <= gpu_toggle_meta;
        gpu_toggle_d1 <= gpu_toggle;
    end  
    assign new_data_pulse = gpu_toggle ^ gpu_toggle_d1;

    logic [7:0] tex_rom [0:16383];
    logic [7:0] tex_data;

    initial begin
        $readmemh("concrete_rgb332_128x128.mem", tex_rom);
    end

    // ---------------------------------------------------------
    // 3. COMPILE-TIME GENERATED 1024-ELEMENT LUT
    // ---------------------------------------------------------
    logic [15:0] STEP_LUT [0:1023];

    initial begin
        STEP_LUT[0] = 16'd0; // Prevent divide by zero
        for (int i = 1; i < 1024; i = i + 1) begin
            STEP_LUT[i] = 16'd32768 / i;
        end
    end

    typedef enum logic {IDLE, DRAW} state_t;
    state_t current_state;

    // ---------------------------------------------------------
    // 4. WIDENED BOUNDARY REGISTERS (10-bit)
    // ---------------------------------------------------------
    logic [7:0]  y_cnt;
    logic [9:0]  wall_top, wall_bottom; // Updated to 10 bits
    logic [15:0] tex_step, texY_fixed;

    logic        valid_s1, is_wall_s1;
    logic [7:0]  y_s1;
    logic [16:0] wr_adr_s1;
    logic [6:0]  texY_s1;

    logic        valid_s2, is_wall_s2;
    logic [7:0]  y_s2; 
    logic [9:0]  wall_top_s2;           // Updated to 10 bits
    logic [16:0] wr_adr_s2;
    logic [13:0] tex_adr_s2;

    logic        valid_s3, is_wall_s3;
    logic [7:0]  y_s3;
    logic [9:0]  wall_top_s3;           // Updated to 10 bits
    logic [16:0] wr_adr_s3;

    always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
            current_state <= IDLE;
            valid_s1      <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    valid_s1 <= 1'b0;
                    if (new_data_pulse) begin
                        y_cnt         <= 0;
                        tex_step      <= STEP_LUT[gpu_height];
                        
                        wall_top      <= (CENTER_ROW > (gpu_height >> 1)) ? (CENTER_ROW - (gpu_height >> 1)) : 0;
                        wall_bottom   <= (CENTER_ROW + (gpu_height >> 1));

                        if (gpu_height > (CENTER_ROW * 2)) 
                            texY_fixed <= (((gpu_height >> 1) - CENTER_ROW) * STEP_LUT[gpu_height]);
                        else 
                            texY_fixed <= 0;
                            
                        current_state <= DRAW;
                    end
                end

                DRAW: begin
                    valid_s1   <= 1'b1;
                    y_s1       <= y_cnt;
                    wr_adr_s1  <= (y_cnt * SCREEN_WIDTH) + gpu_column;
                    
                    // Implicit 0-padding of y_cnt (8-bit) against wall boundaries (10-bit) works perfectly here
                    is_wall_s1 <= (y_cnt >= wall_top) && (y_cnt <= wall_bottom);
                    texY_s1    <= texY_fixed[14:8];

                    if (y_cnt >= wall_top && y_cnt <= wall_bottom) begin
                        texY_fixed <= texY_fixed + tex_step;
                    end

                    if (y_cnt == 239) current_state <= IDLE;
                    else              y_cnt <= y_cnt + 1;
                end
            endcase
        end
    end

    always_ff @(posedge gpu_clk) begin
        valid_s2    <= valid_s1;
        y_s2        <= y_s1;
        wall_top_s2 <= wall_top;
        wr_adr_s2   <= wr_adr_s1;
        is_wall_s2  <= is_wall_s1;
        
        tex_adr_s2  <= {texY_s1, gpu_texX[6:0]};
    end

    always_ff @(posedge gpu_clk) begin
        tex_data    <= tex_rom[tex_adr_s2];
        
        valid_s3    <= valid_s2;
        y_s3        <= y_s2;
        wall_top_s3 <= wall_top_s2;
        wr_adr_s3   <= wr_adr_s2;
        is_wall_s3  <= is_wall_s2;
    end

    assign wr_en  = valid_s3;
    assign wr_adr = wr_adr_s3;

    always_comb begin
        if (!is_wall_s3) data = (y_s3 < wall_top_s3) ? 8'h33 : 8'h77; 
        else             data = tex_data;
    end

endmodule
