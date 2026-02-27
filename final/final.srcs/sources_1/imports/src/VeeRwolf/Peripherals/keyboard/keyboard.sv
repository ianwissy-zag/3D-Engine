module wb_ps2_keyboard (
    // Wishbone Signals
    input  logic        wb_clk_i,
    input  logic        wb_rst_i,
    input  logic [3:0]  wb_adr_i,    
    input  logic [31:0] wb_dat_i,
    output logic [31:0] wb_dat_o,
    input  logic        wb_we_i,
    input  logic        wb_stb_i,
    input  logic        wb_cyc_i,
    output logic        wb_ack_o,

    // PS2 variables
    input  logic        ps2_clk,
    input  logic        ps2_data
);

    // Wishbone Control Signals
    wire wb_valid_cycle = wb_cyc_i && wb_stb_i;
    wire wb_read_en     = wb_valid_cycle && !wb_we_i && !wb_ack_o;

    // FSM States
    typedef enum logic {
        SHIFTING,
        DECODE
    } state_t;

    state_t state, state_next;

    // FSM Registers
    logic [10:0] shift_reg,       shift_reg_next;     // Raw data from the keyboard
    logic [3:0]  bit_count,       bit_count_next;     // Tracks incoming bits
    logic        is_break_code,   is_break_code_next; // Flags if 0xF0 was received
    logic [7:0]  key_reg,         key_reg_next;       // Scan Code
    logic        ready_reg,       ready_reg_next;     // High on new key
    logic        release_reg,     release_reg_next;   // High on key release

    // Clock sync because keyboard clock is slow
    logic [2:0] ps2_clk_sync;
    logic [2:0] ps2_data_sync;

    always_ff @(posedge wb_clk_i) begin
        ps2_clk_sync  <= {ps2_clk_sync[1:0], ps2_clk};
        ps2_data_sync <= {ps2_data_sync[1:0], ps2_data};
    end

    // Falling edge detection (Don't want to always_ff an external clock)
    wire ps2_clk_falling = (ps2_clk_sync[2:1] == 2'b10);

    // State Transition
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            state         <= SHIFTING;
            shift_reg     <= 11'd0;
            bit_count     <= 4'd0;
            is_break_code <= 1'b0;
            key_reg       <= 8'h00;
            ready_reg     <= 1'b0;
            release_reg   <= 1'b0;
        end else begin
            state         <= state_next;
            shift_reg     <= shift_reg_next;
            bit_count     <= bit_count_next;
            is_break_code <= is_break_code_next;
            key_reg       <= key_reg_next;
            ready_reg     <= ready_reg_next;
            release_reg   <= release_reg_next;
        end
    end

    // Next State Logic
    always_comb begin
        state_next         = state;
        shift_reg_next     = shift_reg;
        bit_count_next     = bit_count;
        is_break_code_next = is_break_code;
        key_reg_next       = key_reg;
        ready_reg_next     = ready_reg;
        release_reg_next   = release_reg;

        // This clears the ready so multiple reads on
        // the same key don't occur.
        if (wb_read_en && wb_adr_i == 4'h3) begin
            ready_reg_next = 1'b0;
        end

        case (state)
            // This is the state where data is read in from the keyboard
            // one bit at a time. 
            SHIFTING: begin
                // Capture incoming bits
                if (ps2_clk_falling) begin
                    // Shift the bits in.
                    shift_reg_next = {ps2_data_sync[2], shift_reg[10:1]};
                    
                    if (bit_count == 4'd10) begin
                        bit_count_next = 4'd0;
                        state_next     = DECODE;
                    end else begin
                        bit_count_next = bit_count + 4'd1;
                    end
                end
            end
            
            // This is the state where the actual key value is 
            // extracted from the data. 
            DECODE: begin
                if (shift_reg[8:1] == 8'hF0) begin
                    is_break_code_next = 1'b1; 
                end else begin
                    // Extract the actuall scancode
                    key_reg_next       = shift_reg[8:1]; 
                    release_reg_next   = is_break_code; 
                    ready_reg_next     = 1'b1;
                    is_break_code_next = 1'b0; 
                end
                
                state_next = SHIFTING; 
            end
        endcase
    end

    // Acknowledgement
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) 
            wb_ack_o <= 1'b0;
        else          
            wb_ack_o <= wb_valid_cycle && !wb_ack_o;
    end

    // Reading
    always_ff @(posedge wb_clk_i) begin
        if (wb_read_en) begin
            case (wb_adr_i) 
                4'h3:    wb_dat_o <= {24'h0, key_reg};     // Current Key
                4'h4:    wb_dat_o <= {31'h0, ready_reg};   // Ready Signal
                4'h5:    wb_dat_o <= {31'h0, release_reg}; // Release Signal
                default: wb_dat_o <= 32'h0;
            endcase
        end else begin
            wb_dat_o <= 32'h0;
        end
    end
endmodule