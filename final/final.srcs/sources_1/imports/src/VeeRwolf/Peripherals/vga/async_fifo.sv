module async_fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 64  // must be power of 2
) (
  // Write domain
  input  logic             wr_clk,
  input  logic             wr_rst,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             wr_full,

  // Read domain
  input  logic             rd_clk,
  input  logic             rd_rst,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             rd_empty
);

  localparam int ADDR_BITS = $clog2(DEPTH);
  localparam int PTR_BITS  = ADDR_BITS + 1; // extra MSB for full/empty

  // Memory
  logic [WIDTH-1:0] mem [0:DEPTH-1];

  // Binary + Gray pointers
  logic [PTR_BITS-1:0] wr_ptr_bin,  wr_ptr_gray;
  logic [PTR_BITS-1:0] rd_ptr_bin,  rd_ptr_gray;

  // Synchronized Gray pointers
  logic [PTR_BITS-1:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
  logic [PTR_BITS-1:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

  // Registered full/empty (THIS breaks the combinational self-loop)
  logic wr_full_reg, wr_full_next;
  logic rd_empty_reg, rd_empty_next;

  // Increment enables (gated by registered flags)
  logic wr_inc, rd_inc;

  // Successor pointers (ptr + inc)
  logic [PTR_BITS-1:0] wr_ptr_bin_succ;
  logic [PTR_BITS-1:0] wr_ptr_gray_succ;

  logic [PTR_BITS-1:0] rd_ptr_bin_succ;
  logic [PTR_BITS-1:0] rd_ptr_gray_succ;

  logic [PTR_BITS-1:0] rd_g;
  logic [PTR_BITS-1:0] rd_g_inv;

  function automatic logic [PTR_BITS-1:0] bin2gray(input logic [PTR_BITS-1:0] b);
    return (b >> 1) ^ b;
  endfunction

  // ----------------------------
  // Write-side logic
  // ----------------------------
  assign wr_inc          = wr_en && !wr_full_reg;
  assign wr_ptr_bin_succ = wr_ptr_bin + (wr_inc ? 1 : 0);
  assign wr_ptr_gray_succ= bin2gray(wr_ptr_bin_succ);

  // Full detection uses successor Gray pointer (no dependence on wr_full_next)
  always_comb begin
    rd_g     = rd_ptr_gray_sync2;
    rd_g_inv = {~rd_g[PTR_BITS-1:PTR_BITS-2], rd_g[PTR_BITS-3:0]};

    // "Would be full after the (potential) write?"
    wr_full_next = (wr_ptr_gray_succ == rd_g_inv);
  end

  always_ff @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_ptr_bin  <= '0;
      wr_ptr_gray <= '0;
      wr_full_reg <= 1'b0;
    end else begin
      wr_full_reg <= wr_full_next;

      if (wr_inc) begin
        mem[wr_ptr_bin[ADDR_BITS-1:0]] <= wr_data;
        wr_ptr_bin  <= wr_ptr_bin_succ;
        wr_ptr_gray <= wr_ptr_gray_succ;
      end
    end
  end

  // Sync read pointer into write clock domain
  always_ff @(posedge wr_clk) begin
    if (wr_rst) begin
      rd_ptr_gray_sync1 <= '0;
      rd_ptr_gray_sync2 <= '0;
    end else begin
      rd_ptr_gray_sync1 <= rd_ptr_gray;
      rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end
  end

  // ----------------------------
  // Read-side logic
  // ----------------------------
  assign rd_inc          = rd_en && !rd_empty_reg;
  assign rd_ptr_bin_succ = rd_ptr_bin + (rd_inc ? 1 : 0);
  assign rd_ptr_gray_succ= bin2gray(rd_ptr_bin_succ);

  // Empty detection uses successor Gray pointer (no dependence on rd_empty_next)
  always_comb begin
    // "Would be empty after the (potential) read?"
    rd_empty_next = (rd_ptr_gray_succ == wr_ptr_gray_sync2);
  end

  always_ff @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_ptr_bin   <= '0;
      rd_ptr_gray  <= '0;
      rd_empty_reg <= 1'b1;
      rd_data      <= '0;
    end else begin
      rd_empty_reg <= rd_empty_next;

      if (rd_inc) begin
        rd_data <= mem[rd_ptr_bin[ADDR_BITS-1:0]];
        rd_ptr_bin  <= rd_ptr_bin_succ;
        rd_ptr_gray <= rd_ptr_gray_succ;
      end
    end
  end

  // Sync write pointer into read clock domain
  always_ff @(posedge rd_clk) begin
    if (rd_rst) begin
      wr_ptr_gray_sync1 <= '0;
      wr_ptr_gray_sync2 <= '0;
    end else begin
      wr_ptr_gray_sync1 <= wr_ptr_gray;
      wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end
  end

  // Outputs are registered (stable, no comb loop)
  assign wr_full  = wr_full_reg;
  assign rd_empty = rd_empty_reg;

endmodule
