module wb_interface (
    // Wishbone Bus Connections
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

    // VGA Frame Buffer Index Register (0x00)
    input logic                 bram_inx,

    // Column Drawing Registers (0x04)
    output logic [8:0]          pixel_column,
    output logic [7:0]          column_color,
    output logic [7:0]          column_height,
    output logic                wb_write_toggle,

    // Frame Calculation Done Register (0x08)
    output logic                fcd,

    // GPU Status Registers (0x0C)
    input  logic                cmd_fifo_empty,
    input  logic                cmd_fifo_full,
    input  logic                busy,

    // GPU Control Registers (0x10)
    output logic                overlay_en,
    //output logic                clear_error,
    //output logic                clear_fifo,
    output logic                prim_mode_en,

    // GPU Command Register (0x14)
    output logic [31:0]         cmd_fifo_wr_data,
    output logic                cmd_fifo_wr_en
);

logic  wb_bram_inx_sync;

// Wishbone Bus Control Logic
assign wb_valid_cycle = wb_cyc_i && wb_stb_i;
assign wb_write_en    = wb_valid_cycle && wb_we_i && !wb_ack_o;
assign wb_read_en     = wb_valid_cycle && !wb_we_i && !wb_ack_o;

always_ff @(posedge wb_clk_i) begin
    if (wb_rst_i) 
        wb_ack_o <= 1'b0;
    else          
        wb_ack_o <= wb_valid_cycle && !wb_ack_o;
end

logic cmd_overflow_sticky;
logic cmd_fifo_empty_sync;

// Register Write Control
always_ff @(posedge wb_clk_i) begin
    if (wb_rst_i) begin
        pixel_column <= '0;
        column_color <= '0;
        column_height <= '0;
        wb_write_toggle <= '0;

        fcd <= '0;

        overlay_en <= '0;
        //clear_error <= '0;
        //clear_fifo <= '0;
        prim_mode_en <= '0;

        cmd_overflow_sticky <= '0;
        cmd_fifo_wr_en <= '0;
        cmd_fifo_wr_data <= '0;
    end
    else if (wb_write_en) begin
	// DEFAULTS every cycle
        cmd_fifo_wr_en <= 1'b0;

        case (wb_adr_i)
            // 0x00: VGA Frame Buffer Index Register
            // Nothing to write to here...

            // 0x04: Column Drawing Data Register
            4'h1: begin
                pixel_column    <= wb_dat_i[8:0];
                column_color    <= wb_dat_i[16:9];
                column_height   <= wb_dat_i[24:17];
                wb_write_toggle <= ~wb_write_toggle;
            end

            // 0x08: Frame Calculation Done Register
            4'h2: begin
                fcd             <= wb_dat_i[0];
            end

            // 0x0C: GPU Status Register
            // Nothing to write to here...

            // 0x10: GPU Control Register
            4'h4: begin
                prim_mode_en    <= wb_dat_i[0];
                //clear_fifo      <= wb_dat_i[1];
                overlay_en      <= wb_dat_i[3];

                if (wb_dat_i[2]) begin
                    cmd_overflow_sticky <= '0;
                end
            end

            // 0x14: GPU Command Register
            4'h5: begin
                if (!cmd_fifo_full) begin
                    cmd_fifo_wr_en      <= 1'b1;
                    cmd_fifo_wr_data    <= wb_dat_i;
                    cmd_overflow_sticky <= cmd_overflow_sticky;
                end
                else begin
                    cmd_fifo_wr_en      <= 1'b0;
                    cmd_fifo_wr_data    <= wb_dat_i;
                    cmd_overflow_sticky <= 1'b1;
                end
            end
        endcase
    end
end

// Register Read Control
always_ff @(posedge wb_clk_i) begin
    if (wb_rst_i) begin
        wb_dat_o <= '0;
    end
    else if (wb_read_en) begin
        case (wb_adr_i)
            // 0x00: VGA Frame Buffer Index
            4'h0: wb_dat_o <= {31'b0, wb_bram_inx_sync};

            // 0x04: Column Drawning Data Register
            4'h1: begin
                wb_dat_o <= {
                    6'b0,
                    wb_write_toggle,
                    column_height,
                    column_color,
                    pixel_column
                };
            end

            // 0x08: Frame Calculation Done Register
            // Nothing to see here...

            // 0x0C: GPU Status Register
            4'h3: wb_dat_o <= {
                28'b0,
                cmd_overflow_sticky,
                cmd_fifo_empty_sync,
                cmd_fifo_full,
                busy
            };

            // 0x10: GPU Control Register
            4'h4: begin
                wb_dat_o <= {
                    28'b0,
                    overlay_en,
                    1'b0,
                    1'b0,
                    prim_mode_en
                };
            end

            // 0x14: GPU Command Register
            // Nothing to see here...

            default: wb_dat_o <= '0;
        endcase
    end
    else begin
        wb_dat_o <= '0;
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

logic cmd_fifo_empty_meta;

always_ff @(posedge wb_clk_i) begin
  if (wb_rst_i) begin
    cmd_fifo_empty_meta <= 1'b1;
    cmd_fifo_empty_sync <= 1'b1;
  end else begin
    cmd_fifo_empty_meta <= cmd_fifo_empty;
    cmd_fifo_empty_sync <= cmd_fifo_empty_meta;
  end
end

endmodule
