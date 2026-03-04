module wb_gpu #(
    parameter int SCREEN_WIDTH = 320,
    parameter int CENTER_ROW   = 120
)(
    // Wishbone bus interface
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
    
    // GPU clock domain
    input  logic                gpu_clk,
    input  logic                gpu_rst,
    input  logic                bram_inx,

    // Framebuffer write ports
    output logic                wr_en,
    output logic [16:0]         wr_adr,
    output logic [7:0]          data,
    
    // 1D Z-Buffer / Height Buffer write ports
    output logic                height_we,
    output logic [8:0]          height_adr,
    output logic [9:0]          height_data,
    
    output logic                fcd 
);
        
    // Wishbone cycle control
    logic wb_valid_cycle, wb_write_en, wb_read_en;
    logic wb_bram_inx_sync, wb_bram_inx_meta;
    
    assign wb_valid_cycle = wb_cyc_i && wb_stb_i;
    assign wb_write_en    = wb_valid_cycle && wb_we_i && !wb_ack_o;
    assign wb_read_en     = wb_valid_cycle && !wb_we_i && !wb_ack_o;

    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) wb_ack_o <= 1'b0;
        else          wb_ack_o <= wb_valid_cycle && !wb_ack_o;
    end
    
    // GPU command registers (Wishbone domain)
    logic [8:0] pixel_column;
    logic [7:0] texX; 
    logic [9:0] height;         
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
                    height          <= wb_dat_i[26:17];
                    wb_write_toggle <= ~wb_write_toggle; 
                end
                4'h2: fcd <= wb_dat_i[0];
            endcase
        end
    end

    // Wishbone read logic
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) wb_dat_o <= '0;
        else if (wb_read_en) begin
            case (wb_adr_i)
                4'h0:    wb_dat_o <= {31'b0, wb_bram_inx_sync};
                default: wb_dat_o <= '0;
            endcase 
        end else wb_dat_o <= '0;
    end
    
    // Synchronize BRAM index status to Wishbone domain
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_bram_inx_meta <= 1'b0;
            wb_bram_inx_sync <= 1'b0;
        end else begin
            wb_bram_inx_meta <= bram_inx;
            wb_bram_inx_sync <= wb_bram_inx_meta;
        end
    end

    // Clock domain crossing (CDC) for column parameters (WB to GPU)
    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_texX,   gpu_texX_meta;
    logic [9:0] gpu_height, gpu_height_meta; 
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
    
    // Texture ROM instance
    logic [7:0] tex_rom [0:16383];
    logic [7:0] tex_data;

    initial begin
        $readmemh("brick_128x128.mem", tex_rom);
    end

    // Division LUT for texture scaling
    logic [15:0] STEP_LUT [0:1023];

    initial begin
        STEP_LUT[0] = 16'd0; // Prevent divide by zero
        for (int i = 1; i < 1024; i = i + 1) begin
            STEP_LUT[i] = 16'd32768 / i;
        end
    end
    
    // Main drawing state machine
    typedef enum logic {IDLE, DRAW} state_t;
    state_t current_state;
    
    logic [7:0]  y_cnt;
    logic [9:0]  wall_top, wall_bottom; 
    logic [15:0] tex_step, texY_fixed;

    // Pipeline Stage 1: Address calculation
    logic        valid_s1, is_wall_s1;
    logic [7:0]  y_s1;
    logic [16:0] wr_adr_s1;
    logic [6:0]  texY_s1;

    // Pipeline Stage 2: Texture fetch routing
    logic        valid_s2, is_wall_s2;
    logic [7:0]  y_s2; 
    logic [9:0]  wall_top_s2;           
    logic [16:0] wr_adr_s2;
    logic [13:0] tex_adr_s2;

    // Pipeline Stage 3: Data output alignment
    logic        valid_s3, is_wall_s3;
    logic [7:0]  y_s3;
    logic [9:0]  wall_top_s3;          
    logic [16:0] wr_adr_s3;

    // State machine logic
    always_ff @(posedge gpu_clk) begin
        if (gpu_rst) begin
            current_state <= IDLE;
            valid_s1      <= 1'b0;
            height_we     <= 1'b0;
        end else begin
            height_we <= 1'b0; 

            case (current_state)
                IDLE: begin
                    valid_s1 <= 1'b0;
                    if (new_data_pulse) begin
                        // Initialize column drawing parameters
                        y_cnt         <= 0;
                        tex_step      <= STEP_LUT[gpu_height];
                        wall_top      <= (CENTER_ROW > (gpu_height >> 1)) ? (CENTER_ROW - (gpu_height >> 1)) : 0;
                        wall_bottom   <= (CENTER_ROW + (gpu_height >> 1));

                        // Handle texture offset for walls larger than screen height
                        if (gpu_height > (CENTER_ROW * 2)) 
                            texY_fixed <= (((gpu_height >> 1) - CENTER_ROW) * STEP_LUT[gpu_height]);
                        else 
                            texY_fixed <= 0;
                            
                        // Store column height in 1D Z-Buffer
                        height_we   <= 1'b1;
                        height_adr  <= gpu_column;
                        height_data <= gpu_height;

                        current_state <= DRAW;
                    end
                end

                DRAW: begin
                    // Feed pipeline stage 1
                    valid_s1   <= 1'b1;
                    y_s1       <= y_cnt;
                    wr_adr_s1  <= (y_cnt * SCREEN_WIDTH) + gpu_column;
                    is_wall_s1 <= (y_cnt >= wall_top) && (y_cnt <= wall_bottom);
                    texY_s1    <= texY_fixed[14:8];

                    // Increment texture pointer within wall bounds
                    if (y_cnt >= wall_top && y_cnt <= wall_bottom) begin
                        texY_fixed <= texY_fixed + tex_step;
                    end

                    // Terminate at bottom of screen (240px tall assumed)
                    if (y_cnt == 239) current_state <= IDLE;
                    else              y_cnt <= y_cnt + 1;
                end
            endcase
        end
    end

    // Pipeline shift registers (S1 -> S2)
    always_ff @(posedge gpu_clk) begin
        valid_s2    <= valid_s1;
        y_s2        <= y_s1;
        wall_top_s2 <= wall_top;
        wr_adr_s2   <= wr_adr_s1;
        is_wall_s2  <= is_wall_s1;
        tex_adr_s2  <= {texY_s1, gpu_texX[6:0]};
    end

    // Pipeline shift registers (S2 -> S3) and Texture ROM read
    always_ff @(posedge gpu_clk) begin
        tex_data    <= tex_rom[tex_adr_s2];
        valid_s3    <= valid_s2;
        y_s3        <= y_s2;
        wall_top_s3 <= wall_top_s2;
        wr_adr_s3   <= wr_adr_s2;
        is_wall_s3  <= is_wall_s2;
    end

    // Final output assignments
    assign wr_en  = valid_s3;
    assign wr_adr = wr_adr_s3;

    // Output multiplexer: select between floor, ceiling, and wall texture
    always_comb begin
        if (!is_wall_s3) data = (y_s3 < wall_top_s3) ? 8'h33 : 8'h77; 
        else             data = tex_data;
    end
endmodule