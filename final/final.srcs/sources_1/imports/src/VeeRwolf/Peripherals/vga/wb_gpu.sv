module wb_gpu #()(
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
    
    // 100 MHz Clock
    input logic                     gpu_clk,

    // VGA Ports (Video Interface)
    output logic                    wr_en,
    output logic [16:0]             wr_adr,
    output  logic [7:0]             data);

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
        end else if (wb_write_en) begin
            
        end
    end

    // Read
    always_ff @(posedge wb_clk_i) begin
        if (wb_read_en) begin
            case (wb_adr_i)
               default: wb_dat_o <= '0;
            endcase 
        end
        else wb_dat_o <= '0;
    end
    
    // Temp assignments 
    always_ff @(posedge gpu_clk) begin
        wr_en <= '0;
        wr_adr <= '0;
        data <= '0;
    end
endmodule