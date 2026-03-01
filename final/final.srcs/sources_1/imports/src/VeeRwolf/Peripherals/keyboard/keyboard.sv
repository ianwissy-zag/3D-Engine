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
    logic [10:0] shift_reg,     shift_reg_next;     // Raw data from the keyboard
    logic [3:0]  bit_count,     bit_count_next;     // Tracks incoming bits
    logic        is_break_code, is_break_code_next; // Flags if 0xF0 was received
    
    // New WASD State Register: [3]=W, [2]=A, [1]=S, [0]=D
    logic [3:0]  wasd_state,    wasd_state_next; 

    // Clock sync because keyboard clock is slow
    logic [2:0] ps2_clk_sync;
    logic [2:0] ps2_data_sync;

    always_ff @(posedge wb_clk_i) begin
        ps2_clk_sync  <= {ps2_clk_sync[1:0], ps2_clk};
        ps2_data_sync <= {ps2_data_sync[1:0], ps2_data};
    end

    // Falling edge detection
    wire ps2_clk_falling = (ps2_clk_sync[2:1] == 2'b10);

    // State Transition
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            state         <= SHIFTING;
            shift_reg     <= 11'd0;
            bit_count     <= 4'd0;
            is_break_code <= 1'b0;
            wasd_state    <= 4'b0000;
        end else begin
            state         <= state_next;
            shift_reg     <= shift_reg_next;
            bit_count     <= bit_count_next;
            is_break_code <= is_break_code_next;
            wasd_state    <= wasd_state_next;
        end
    end

    // Next State Logic
    always_comb begin
        state_next         = state;
        shift_reg_next     = shift_reg;
        bit_count_next     = bit_count;
        is_break_code_next = is_break_code;
        wasd_state_next    = wasd_state;

        case (state)
            SHIFTING: begin
                if (ps2_clk_falling) begin
                    // Wait for a valid Start bit (0) before we begin counting.
                    if (bit_count == 4'd0 && ps2_data_sync[1] == 1'b1) begin
                        bit_count_next = 4'd0; // Ignore false starts
                    end else begin
                        // Shift data in using [1], which is strictly aligned with the clock low state
                        shift_reg_next = {ps2_data_sync[1], shift_reg[10:1]};
                        
                        if (bit_count == 4'd10) begin
                            bit_count_next = 4'd0;
                            state_next     = DECODE;
                        end else begin
                            bit_count_next = bit_count + 4'd1;
                        end
                    end
                end
            end
            
            DECODE: begin
                // Frame verification: Start bit MUST be 0, Stop bit MUST be 1
                if (shift_reg[0] == 1'b0 && shift_reg[10] == 1'b1) begin
                    
                    if (shift_reg[8:1] == 8'hF0) begin
                        is_break_code_next = 1'b1; 
                    end else begin
                        case (shift_reg[8:1])
                            8'h1D: wasd_state_next[3] = !is_break_code; // W
                            8'h1C: wasd_state_next[2] = !is_break_code; // A
                            8'h1B: wasd_state_next[1] = !is_break_code; // S
                            8'h23: wasd_state_next[0] = !is_break_code; // D
                            default: ; // Ignore other scancodes
                        endcase
                        // Reset break code after applying it
                        is_break_code_next = 1'b0; 
                    end
                    
                end else begin
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
            // Output WASD state at Address 0
            if (wb_adr_i == 4'h0) begin
                wb_dat_o <= {28'h0, wasd_state}; 
            end else begin
                wb_dat_o <= 32'h0;
            end
        end else begin
            wb_dat_o <= 32'h0;
        end
    end
endmodule