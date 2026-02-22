module wb_ps2_keyboard (
    // Wishbone Signals
    input  logic        wb_clk_i,    // 12.5 MHz
    input  logic        wb_rst_i,
    input  logic [3:0]  wb_adr_i,    
    input  logic [31:0] wb_dat_i,
    output logic [31:0] wb_dat_o,
    input  logic        wb_we_i,
    input  logic        wb_stb_i,
    input  logic        wb_cyc_i,
    output logic        wb_ack_o,

    // PS/2 Physical Interface
    input  logic        ps2_clk,
    input  logic        ps2_data
);

    // --- Internal Registers ---
    logic [7:0]  key_reg;     // Holds the captured scan code
    logic        ready_reg;   // High when a new key is available
    logic [10:0] shift_reg;   // PS/2 frame: [Stop, Parity, D7..D0, Start]
    logic [3:0]  bit_count;   // Tracks incoming bits

    // --- Synchronization & Edge Detection ---
    logic [2:0] ps2_clk_sync;
    logic [2:0] ps2_data_sync;

    always_ff @(posedge wb_clk_i) begin
        ps2_clk_sync  <= {ps2_clk_sync[1:0], ps2_clk};
        ps2_data_sync <= {ps2_data_sync[1:0], ps2_data};
    end

    // PS/2 data is sampled on the falling edge of the PS/2 clock
    wire ps2_clk_falling = (ps2_clk_sync[2:1] == 2'b10);

    // --- PS/2 Receiver Logic ---
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            bit_count <= 4'd0;
            ready_reg <= 1'b0;
            key_reg   <= 8'h00;
        end else begin
            // Capture incoming bits
            if (ps2_clk_falling) begin
                // Shift in from the top so the bits are in the right place at the end
                shift_reg <= {ps2_data_sync[2], shift_reg[10:1]};
                
                if (bit_count == 4'd10) begin
                    bit_count <= 4'd0;
                    ready_reg <= 1'b1;
                    // Grab from the data line directly for the last bit or use the correctly shifted index
                    key_reg <= shift_reg[9:2]; 
                end else begin
                    bit_count <= bit_count + 4'd1;
                end
            end 
            // "Auto-clear" logic: Clear ready flag when the CPU reads address 3
            if (wb_read_en && wb_adr_i == 4'h3) begin
                ready_reg <= 1'b0;
            end
        end
    end

    // --- Wishbone Interface Logic ---
    wire wb_valid_cycle = wb_cyc_i && wb_stb_i;
    wire wb_read_en    = wb_valid_cycle && !wb_we_i && !wb_ack_o;

    // Acknowledgement
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) 
            wb_ack_o <= 1'b0;
        else          
            wb_ack_o <= wb_valid_cycle && !wb_ack_o;
    end

    // Bus Read Mapping
    always_ff @(posedge wb_clk_i) begin
        if (wb_read_en) begin
            case (wb_adr_i) 
                4'h3:    wb_dat_o <= {24'h0, key_reg};   // Current Key
                4'h4:    wb_dat_o <= {31'h0, ready_reg}; // Ready Signal
                default: wb_dat_o <= 32'h0;
            endcase
        end else begin
            wb_dat_o <= 32'h0;
        end
    end

endmodule