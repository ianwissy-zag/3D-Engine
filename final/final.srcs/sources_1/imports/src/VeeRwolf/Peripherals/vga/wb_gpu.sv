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
    
    logic [8:0] pixel_column;
    logic [7:0] texX; 
    logic [7:0] height;
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
                    height          <= wb_dat_i[24:17];
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

    logic [8:0] gpu_column, gpu_column_meta;
    logic [7:0] gpu_texX,   gpu_texX_meta;
    logic [7:0] gpu_height, gpu_height_meta;
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

    localparam logic [15:0] STEP_LUT [0:255] = '{
        16'd0,    16'd32768, 16'd16384, 16'd10922, 16'd8192, 16'd6553, 16'd5461, 16'd4681,
        16'd4096, 16'd3640,  16'd3276,  16'd2978,  16'd2730, 16'd2520, 16'd2340, 16'd2184,
        16'd2048, 16'd1927,  16'd1820,  16'd1724,  16'd1638, 16'd1560, 16'd1489, 16'd1424,
        16'd1365, 16'd1310,  16'd1260,  16'd1213,  16'd1170, 16'd1130, 16'd1092, 16'd1057,
        16'd1024, 16'd992,   16'd963,   16'd936,   16'd910,  16'd885,  16'd862,  16'd840,
        16'd819,  16'd799,   16'd780,   16'd762,   16'd744,  16'd728,  16'd712,  16'd697,
        16'd682,  16'd668,   16'd655,   16'd642,   16'd630,  16'd618,  16'd606,  16'd595,
        16'd585,  16'd574,   16'd564,   16'd555,   16'd546,  16'd537,  16'd528,  16'd520,
        16'd512,  16'd504,   16'd496,   16'd489,   16'd481,  16'd474,  16'd468,  16'd461,
        16'd455,  16'd448,   16'd442,   16'd436,   16'd431,  16'd425,  16'd420,  16'd414,
        16'd409,  16'd404,   16'd399,   16'd394,   16'd390,  16'd385,  16'd381,  16'd376,
        16'd372,  16'd368,   16'd364,   16'd360,   16'd356,  16'd352,  16'd348,  16'd344,
        16'd341,  16'd337,   16'd334,   16'd330,   16'd327,  16'd324,  16'd321,  16'd318,
        16'd315,  16'd312,   16'd309,   16'd306,   16'd303,  16'd300,  16'd297,  16'd295,
        16'd292,  16'd289,   16'd287,   16'd284,   16'd282,  16'd280,  16'd277,  16'd275,
        16'd273,  16'd270,   16'd268,   16'd266,   16'd264,  16'd262,  16'd260,  16'd258,
        16'd256,  16'd254,   16'd252,   16'd250,   16'd248,  16'd246,  16'd244,  16'd242,
        16'd240,  16'd239,   16'd237,   16'd235,   16'd234,  16'd232,  16'd230,  16'd229,
        16'd227,  16'd225,   16'd224,   16'd222,   16'd221,  16'd219,  16'd218,  16'd216,
        16'd215,  16'd214,   16'd212,   16'd211,   16'd209,  16'd208,  16'd207,  16'd206,
        16'd204,  16'd203,   16'd202,   16'd201,   16'd199,  16'd198,  16'd197,  16'd196,
        16'd195,  16'd193,   16'd192,   16'd191,   16'd190,  16'd189,  16'd188,  16'd187,
        16'd186,  16'd185,   16'd184,   16'd183,   16'd182,  16'd181,  16'd180,  16'd179,
        16'd178,  16'd177,   16'd176,   16'd175,   16'd174,  16'd173,  16'd172,  16'd171,
        16'd170,  16'd169,   16'd168,   16'd168,   16'd167,  16'd166,  16'd165,  16'd164,
        16'd163,  16'd163,   16'd162,   16'd161,   16'd160,  16'd159,  16'd159,  16'd158,
        16'd157,  16'd156,   16'd156,   16'd155,   16'd154,  16'd153,  16'd153,  16'd152,
        16'd151,  16'd151,   16'd150,   16'd149,   16'd148,  16'd148,  16'd147,  16'd146,
        16'd146,  16'd145,   16'd145,   16'd144,   16'd143,  16'd143,  16'd142,  16'd141,
        16'd141,  16'd140,   16'd140,   16'd139,   16'd138,  16'd138,  16'd137,  16'd137,
        16'd136,  16'd135,   16'd135,   16'd134,   16'd134,  16'd133,  16'd133,  16'd132,
        16'd132,  16'd131,   16'd131,   16'd130,   16'd130,  16'd129,  16'd129,  16'd128
    };

    typedef enum logic {IDLE, DRAW} state_t;
    state_t current_state;

    logic [7:0]  y_cnt, wall_top, wall_bottom;
    logic [15:0] tex_step, texY_fixed;

    logic        valid_s1, is_wall_s1;
    logic [7:0]  y_s1;
    logic [16:0] wr_adr_s1;
    logic [6:0]  texY_s1;

    logic        valid_s2, is_wall_s2;
    logic [7:0]  y_s2, wall_top_s2;
    logic [16:0] wr_adr_s2;
    logic [13:0] tex_adr_s2;

    logic        valid_s3, is_wall_s3;
    logic [7:0]  y_s3, wall_top_s3;
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