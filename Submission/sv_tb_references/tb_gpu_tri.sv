//------------------------------------------------------------------------------
// File       : tb_gpu_tri.sv
// Author     : Nelson Rodriguez-Ortiz (assisted with ChatGPT)
// Description: SystemVerilog testbench for the GPU triangle rasterization path.
//              This testbench instantiates and verifies the interaction between
//              the async_fifo, wb_gpu, bram, and vga modules.
//
//              Main verification goals:
//              1. Drive triangle commands into async_fifo.
//              2. Verify wb_gpu triangle rasterization writes:
//                   - busy
//                   - wr_en
//                   - wr_adr
//                   - data
//              3. Verify expected pixel data is written into BRAM.
//              4. Verify VGA output color for a known pixel inside the triangle
//                 after framebuffer flip.
//
// Notes      :
//              - Raycasting functionality is not the focus of this testbench.
//              - pixel_column, color, height, and write_toggle are tied off so
//                the triangle rasterization engine can be isolated.
//              - This testbench was simulated in QuestaSim.
// Dependencies:
//              - async_fifo.sv
//              - wb_gpu.sv
//              - bram.sv
//              - vga.sv
//              - dtg.sv
//              - image.mem
//------------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_gpu_tri;

  // --------------------------------------------------------------------------
  // Clocks / resets
  // --------------------------------------------------------------------------
  logic clk;        // 12.5 MHz  (FIFO write side)
  logic clk_gpu;    // 100  MHz  (GPU / BRAM write side)
  logic clk_vga;    // 25   MHz  (VGA / BRAM read side)

  logic wb_rst;
  logic rst_gpu;
  logic rst_vga;

  localparam time CLK_WB_PERIOD  = 80ns; // 12.5 MHz
  localparam time CLK_GPU_PERIOD = 10ns; // 100 MHz
  localparam time CLK_VGA_PERIOD = 40ns; // 25 MHz

  localparam int FB_WIDTH  = 320;
  localparam int FB_HEIGHT = 240;
  localparam int FB_DEPTH  = 76800;

  initial begin
    clk = 1'b0;
    forever #(CLK_WB_PERIOD/2) clk = ~clk;
  end

  initial begin
    clk_gpu = 1'b0;
    forever #(CLK_GPU_PERIOD/2) clk_gpu = ~clk_gpu;
  end

  initial begin
    clk_vga = 1'b0;
    forever #(CLK_VGA_PERIOD/2) clk_vga = ~clk_vga;
  end

  // --------------------------------------------------------------------------
  // wb_gpu tie-offs / controls
  // --------------------------------------------------------------------------
  logic [8:0] pixel_column;
  logic [7:0] color;
  logic [7:0] height;
  logic       write_toggle;
  logic       overlay_en;
  logic       prim_mode_en;

  // --------------------------------------------------------------------------
  // FIFO write side
  // --------------------------------------------------------------------------
  logic        cmd_fifo_wr_en;
  logic [31:0] cmd_fifo_wr_data;
  logic        cmd_fifo_full;

  // FIFO read side / GPU connections
  logic        cmd_fifo_rd_en;
  logic [31:0] cmd_fifo_rd_data;
  logic        cmd_fifo_empty;

  // --------------------------------------------------------------------------
  // GPU outputs
  // --------------------------------------------------------------------------
  logic        busy;
  logic        wr_en;
  logic [16:0] wr_adr;
  logic [7:0]  data;

  // --------------------------------------------------------------------------
  // BRAM / VGA interconnect
  // --------------------------------------------------------------------------
  logic        vga_rd_en;
  logic [16:0] vga_rd_adr;
  logic        vga_bram_inx;
  logic        gpu_bram_inx;
  logic [7:0]  bram_data_out;

  logic [3:0]  VGA_Red;
  logic [3:0]  VGA_Green;
  logic [3:0]  VGA_Blue;
  logic        vsync;
  logic        hsync;

  logic        fcd;

  // --------------------------------------------------------------------------
  // Triangle test variables
  // --------------------------------------------------------------------------
  logic [8:0] X0, X1, X2;
  logic [7:0] Y0, Y1, Y2;
  logic [7:0] TRI_COL;

  localparam logic [8:0] SAMPLE_X = 9'd12;
  localparam logic [7:0] SAMPLE_Y = 8'd12;

  logic [16:0] SAMPLE_ADR;

  // --------------------------------------------------------------------------
  // Error counters split by process (Questa always_ff rule)
  // --------------------------------------------------------------------------
  integer mon_errors;
  integer ctrl_errors;

  int unsigned wr_pulses;

  // --------------------------------------------------------------------------
  // Expected sets
  // need_map: outstanding pixels not yet observed from GPU write stream
  // exp_map : full expected triangle footprint, kept for post-write BRAM checks
  // --------------------------------------------------------------------------
  typedef int unsigned uaddr_t;
  bit need_map [uaddr_t];
  bit seen_map [uaddr_t];
  bit exp_map  [uaddr_t];

  int unsigned expected_count;
  logic [7:0]  expected_color;

  // --------------------------------------------------------------------------
  // DUT instances
  // --------------------------------------------------------------------------
  async_fifo #(.WIDTH(32), .DEPTH(64)) u_cmd_fifo (
    .wr_clk  (clk),
    .wr_rst  (wb_rst),
    .wr_en   (cmd_fifo_wr_en),
    .wr_data (cmd_fifo_wr_data),
    .wr_full (cmd_fifo_full),

    .rd_clk  (clk_gpu),
    .rd_rst  (rst_gpu),
    .rd_en   (cmd_fifo_rd_en),
    .rd_data (cmd_fifo_rd_data),
    .rd_empty(cmd_fifo_empty)
  );

  wb_gpu #(
    .SCREEN_WIDTH(320),
    .CENTER_ROW(120)
  ) u_gpu (
    .gpu_clk          (clk_gpu),
    .gpu_rst          (rst_gpu),
    .pixel_column     (pixel_column),
    .color            (color),
    .height           (height),
    .write_toggle     (write_toggle),
    .overlay_en       (overlay_en),
    .prim_mode_en     (prim_mode_en),
    .cmd_fifo_empty   (cmd_fifo_empty),
    .cmd_fifo_rd_data (cmd_fifo_rd_data),

    .cmd_fifo_rd_en   (cmd_fifo_rd_en),
    .busy             (busy),
    .wr_en            (wr_en),
    .wr_adr           (wr_adr),
    .data             (data)
  );

  bram #(
    .DATA_WIDTH(8),
    .DEPTH(FB_DEPTH),
    .ADR_WIDTH(17)
  ) u_bram (
    .vga_clk      (clk_vga),
    .gpu_clk      (clk_gpu),
    .gpu_rst      (rst_gpu),

    .vga_bram_inx (vga_bram_inx),
    .gpu_bram_inx (gpu_bram_inx),

    .data_in      (data),
    .data_out     (bram_data_out),
    .rd_en        (vga_rd_en),
    .wr_en        (wr_en),
    .adr_wr       (wr_adr),
    .adr_rd       (vga_rd_adr)
  );

  vga u_vga (
    .rd_en      (vga_rd_en),
    .rd_adr     (vga_rd_adr),
    .bram_inx   (vga_bram_inx),
    .data       (bram_data_out),

    .clk_vga    (clk_vga),
    .rst        (rst_vga),
    .VGA_Red    (VGA_Red),
    .VGA_Green  (VGA_Green),
    .VGA_Blue   (VGA_Blue),
    .vsync      (vsync),
    .hsync      (hsync),

    .fcd        (fcd),
    .busy       (busy)
  );

  // --------------------------------------------------------------------------
  // Helpers: command encoding
  // --------------------------------------------------------------------------
  function automatic logic [31:0] pack_vtx(
    input logic [1:0] opcode,
    input logic [8:0] x,
    input logic [7:0] y
  );
    logic [31:0] w;
    begin
      w = 32'h0;
      w[31:30] = opcode;
      w[29:21] = x;
      w[20:13] = y;
      pack_vtx = w;
    end
  endfunction

  function automatic logic [31:0] pack_submit(input logic [7:0] tri_col);
    logic [31:0] w;
    begin
      w = 32'h0;
      w[31:30] = 2'b11;
      w[29:22] = tri_col;
      pack_submit = w;
    end
  endfunction

  // --------------------------------------------------------------------------
  // Reference model helpers
  // --------------------------------------------------------------------------
  function automatic logic signed [23:0] edge_eval(
    input logic [8:0]  x,
    input logic [7:0]  y,
    input logic [8:0]  xa, input logic [7:0] ya,
    input logic [8:0]  xb, input logic [7:0] yb
  );
    logic signed [10:0] xs, xas, xbs;
    logic signed [9:0]  ys, yas, ybs;
    logic signed [10:0] dx;
    logic signed [9:0]  dy;
    logic signed [23:0] e;
    begin
      xs  = $signed({1'b0, x});
      ys  = $signed({1'b0, y});
      xas = $signed({1'b0, xa});
      yas = $signed({1'b0, ya});
      xbs = $signed({1'b0, xb});
      ybs = $signed({1'b0, yb});
      dx = xbs - xas;
      dy = ybs - yas;
      e  = ( (ys - yas) * dx ) - ( (xs - xas) * dy );
      edge_eval = e;
    end
  endfunction

  function automatic logic inside_tri_ref(
    input logic [8:0] x,
    input logic [7:0] y,
    input logic [8:0] x0, input logic [7:0] y0,
    input logic [8:0] x1, input logic [7:0] y1,
    input logic [8:0] x2, input logic [7:0] y2
  );
    logic signed [23:0] e01, e12, e20;
    logic ge_all, le_all;
    begin
      e01 = edge_eval(x,y, x0,y0, x1,y1);
      e12 = edge_eval(x,y, x1,y1, x2,y2);
      e20 = edge_eval(x,y, x2,y2, x0,y0);
      ge_all = (e01 >= 0) && (e12 >= 0) && (e20 >= 0);
      le_all = (e01 <= 0) && (e12 <= 0) && (e20 <= 0);
      inside_tri_ref = ge_all || le_all;
    end
  endfunction

  function automatic logic [16:0] addr_of(input logic [8:0] x, input logic [7:0] y);
    logic [16:0] a;
    begin
      a = ({9'd0,y} << 8) + ({9'd0,y} << 6) + {8'd0,x};
      addr_of = a;
    end
  endfunction

  function automatic logic [3:0] red_map(input logic [7:0] c);
    begin
      red_map = {c[7:5], c[5]};
    end
  endfunction

  function automatic logic [3:0] green_map(input logic [7:0] c);
    begin
      green_map = {c[4:2], c[2]};
    end
  endfunction

  function automatic logic [3:0] blue_map(input logic [7:0] c);
    begin
      blue_map = {c[1:0], c[1:0]};
    end
  endfunction

  // --------------------------------------------------------------------------
  // Expected set support
  // --------------------------------------------------------------------------
  task automatic clear_maps();
    uaddr_t k;
    begin
      foreach (need_map[k]) need_map.delete(k);
      foreach (seen_map[k]) seen_map.delete(k);
      foreach (exp_map[k])  exp_map.delete(k);
      expected_count = 0;
    end
  endtask

  task automatic build_expected_triangle(
    input logic [8:0] x0, input logic [7:0] y0,
    input logic [8:0] x1, input logic [7:0] y1,
    input logic [8:0] x2, input logic [7:0] y2,
    input logic [7:0] col
  );
    logic [8:0] min_x, max_x;
    logic [7:0] min_y, max_y;
    int xi, yi;
    logic [16:0] a;
    uaddr_t key;
    logic [8:0] x_pix;
    logic [7:0] y_pix;
    begin
      clear_maps();
      expected_color = col;

      min_x = (x0<x1) ? ((x0<x2)?x0:x2) : ((x1<x2)?x1:x2);
      max_x = (x0>x1) ? ((x0>x2)?x0:x2) : ((x1>x2)?x1:x2);
      min_y = (y0<y1) ? ((y0<y2)?y0:y2) : ((y1<y2)?y1:y2);
      max_y = (y0>y1) ? ((y0>y2)?y0:y2) : ((y1>y2)?y1:y2);

      for (yi = min_y; yi <= max_y; yi++) begin
        for (xi = min_x; xi <= max_x; xi++) begin
          x_pix = 9'(xi);
          y_pix = 8'(yi);

          if (inside_tri_ref(x_pix, y_pix, x0, y0, x1, y1, x2, y2)) begin
            a   = addr_of(x_pix, y_pix);
            key = uaddr_t'(a);

            if (!need_map.exists(key)) begin
              need_map[key] = 1'b1;
              exp_map[key]  = 1'b1;
              expected_count++;
            end
          end
        end
      end

      $display("[TB] Expected triangle writes: %0d unique pixels", expected_count);

      if (expected_count == 0) begin
        $error("[TB] Reference model produced 0 pixels.");
        ctrl_errors = ctrl_errors + 1;
      end
    end
  endtask

  function automatic int unsigned remaining_expected();
    uaddr_t k;
    int unsigned c;
    begin
      c = 0;
      foreach (need_map[k]) begin
        if (need_map[k]) c++;
      end
      return c;
    end
  endfunction

  // --------------------------------------------------------------------------
  // FIFO push task
  // --------------------------------------------------------------------------
  task automatic fifo_push(input logic [31:0] w);
    begin
      @(posedge clk);
      while (cmd_fifo_full) @(posedge clk);

      cmd_fifo_wr_data <= w;
      cmd_fifo_wr_en   <= 1'b1;
      @(posedge clk);
      cmd_fifo_wr_en   <= 1'b0;
      cmd_fifo_wr_data <= '0;
    end
  endtask

  // --------------------------------------------------------------------------
  // Monitor GPU write stream against expected triangle addresses
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_gpu) begin
    if (rst_gpu) begin
      mon_errors <= 0;
      wr_pulses  <= 0;
    end else begin
      if (wr_en) begin
        uaddr_t key;
        key = uaddr_t'(wr_adr);
        wr_pulses <= wr_pulses + 1;

        if (!need_map.exists(key) || !need_map[key]) begin
          $error("[TB] UNEXPECTED WRITE: adr=%0d (0x%0h) data=0x%0h t=%0t",
                 wr_adr, wr_adr, data, $time);
          mon_errors <= mon_errors + 1;
        end else if (seen_map.exists(key) && seen_map[key]) begin
          $error("[TB] DUPLICATE WRITE: adr=%0d (0x%0h) data=0x%0h t=%0t",
                 wr_adr, wr_adr, data, $time);
          mon_errors <= mon_errors + 1;
        end else begin
          if (data !== expected_color) begin
            $error("[TB] DATA MISMATCH: adr=%0d got=0x%0h expected=0x%0h t=%0t",
                   wr_adr, data, expected_color, $time);
            mon_errors <= mon_errors + 1;
          end

          seen_map[key] = 1'b1;
          need_map[key] = 1'b0;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Main test
  // --------------------------------------------------------------------------
  initial begin : main
    int unsigned guard;
    int unsigned cycles;
    int unsigned vga_cycles;
    int unsigned write_bank;
    int unsigned full_addr;
    uaddr_t k;

    logic [3:0] exp_red;
    logic [3:0] exp_green;
    logic [3:0] exp_blue;

    SAMPLE_ADR = addr_of(SAMPLE_X, SAMPLE_Y);

    ctrl_errors = 0;

    // defaults
    cmd_fifo_wr_en   = 1'b0;
    cmd_fifo_wr_data = '0;

    pixel_column  = 9'd0;
    color         = 8'h00;
    height        = 8'h00;

    write_toggle  = 1'b0; // keep raycast quiet
    overlay_en    = 1'b1;
    prim_mode_en  = 1'b1;

    fcd           = 1'b0;

    wb_rst  = 1'b1;
    rst_gpu = 1'b1;
    rst_vga = 1'b1;

    repeat (5)  @(posedge clk);
    repeat (10) @(posedge clk_gpu);
    repeat (10) @(posedge clk_vga);

    wb_rst  = 1'b0;
    rst_gpu = 1'b0;
    rst_vga = 1'b0;

    repeat (20) @(posedge clk_gpu);

    // Triangle
    X0 = 9'd10; Y0 = 8'd10;
    X1 = 9'd20; Y1 = 8'd10;
    X2 = 9'd10; Y2 = 8'd20;
    TRI_COL = 8'hA5;

    build_expected_triangle(X0, Y0, X1, Y1, X2, Y2, TRI_COL);

    if (!inside_tri_ref(SAMPLE_X, SAMPLE_Y, X0, Y0, X1, Y1, X2, Y2)) begin
      $error("[TB] SAMPLE_X/SAMPLE_Y is not inside the expected triangle.");
      ctrl_errors = ctrl_errors + 1;
    end

    fifo_push(pack_vtx(2'b00, X0, Y0));
    fifo_push(pack_vtx(2'b01, X1, Y1));
    fifo_push(pack_vtx(2'b10, X2, Y2));
    fifo_push(pack_submit(TRI_COL));

    $display("[TB] Commands pushed. Waiting for busy...");

    // Wait for busy assert
    guard = 0;
    while (busy !== 1'b1) begin
      @(posedge clk_gpu);
      guard++;
      if (guard > 20000) begin
        $error("[TB] TIMEOUT: busy never asserted.");
        ctrl_errors = ctrl_errors + 1;
        disable main;
      end
    end
    $display("[TB] busy asserted at t=%0t", $time);

    // Wait for raster completion
    cycles = 0;
    while (1) begin
      @(posedge clk_gpu);
      cycles++;

      if ((busy === 1'b0) && (remaining_expected() == 0) && (cmd_fifo_empty === 1'b1)) begin
        $display("[TB] Raster complete at t=%0t after %0d gpu cycles", $time, cycles);
        break;
      end

      if (cycles > 500000) begin
        $error("[TB] TIMEOUT waiting for completion. remaining=%0d busy=%0b empty=%0b",
               remaining_expected(), busy, cmd_fifo_empty);
        ctrl_errors = ctrl_errors + 1;
        break;
      end
    end

    if (remaining_expected() != 0) begin
      $error("[TB] Missing %0d expected writes.", remaining_expected());
      ctrl_errors = ctrl_errors + 1;
    end

    if (wr_pulses == 0) begin
      $error("[TB] No wr_en pulses observed.");
      ctrl_errors = ctrl_errors + 1;
    end

    // ----------------------------------------------------------------------
    // BRAM content check
    // GPU should have written into the current gpu_bram_inx bank
    // ----------------------------------------------------------------------
    write_bank = gpu_bram_inx;

    $display("[TB] Checking BRAM contents in bank %0d", write_bank);

    foreach (exp_map[k]) begin
      if (exp_map[k]) begin
        full_addr = k + (write_bank * FB_DEPTH);
        if (u_bram.memory[full_addr] !== TRI_COL) begin
          $error("[TB] BRAM MISMATCH: full_addr=%0d fb_adr=%0d got=0x%0h expected=0x%0h",
                 full_addr, k, u_bram.memory[full_addr], TRI_COL);
          ctrl_errors = ctrl_errors + 1;
        end
      end
    end

    // ----------------------------------------------------------------------
    // VGA check
    // Request frame flip, then wait until VGA is reading/displaying the bank
    // we just wrote. Verify RGB at a known pixel inside triangle.
    // ----------------------------------------------------------------------
    exp_red   = red_map(TRI_COL);
    exp_green = green_map(TRI_COL);
    exp_blue  = blue_map(TRI_COL);

    $display("[TB] Requesting frame-buffer flip...");
    fcd = 1'b1;

    // Wait until VGA flips to the bank GPU wrote
    vga_cycles = 0;
    while (vga_bram_inx !== write_bank[0]) begin
      @(posedge clk_vga);
      vga_cycles++;
      if (vga_cycles > 1000000) begin
        $error("[TB] TIMEOUT waiting for VGA buffer flip. vga_bram_inx=%0b write_bank=%0d",
               vga_bram_inx, write_bank);
        ctrl_errors = ctrl_errors + 1;
        disable main;
      end
    end

    $display("[TB] VGA flip observed at t=%0t. vga_bram_inx=%0b", $time, vga_bram_inx);

    // Keep fcd high or low; either is fine once flip occurred. Drop it here.
    fcd = 1'b0;

    // Wait until VGA is actively displaying SAMPLE_X/SAMPLE_Y
    // Use hierarchical refs inside vga.sv because they are already aligned
    // to the displayed RGB path.
    vga_cycles = 0;
    while (1) begin
      @(posedge clk_vga);
      vga_cycles++;

      if ((u_vga.px_en_d2 == 1'b1) &&
          (u_vga.scaled_x == SAMPLE_X) &&
          (u_vga.scaled_y == SAMPLE_Y) &&
          (vga_bram_inx == write_bank[0])) begin

        if ((VGA_Red   !== exp_red)   ||
            (VGA_Green !== exp_green) ||
            (VGA_Blue  !== exp_blue)) begin
          $error("[TB] VGA COLOR MISMATCH at (%0d,%0d): got RGB=(%0h,%0h,%0h) expected=(%0h,%0h,%0h)",
                 SAMPLE_X, SAMPLE_Y,
                 VGA_Red, VGA_Green, VGA_Blue,
                 exp_red, exp_green, exp_blue);
          ctrl_errors = ctrl_errors + 1;
        end else begin
          $display("[TB] VGA color check passed at (%0d,%0d): RGB=(%0h,%0h,%0h)",
                   SAMPLE_X, SAMPLE_Y, VGA_Red, VGA_Green, VGA_Blue);
        end
        break;
      end

      if (vga_cycles > 1000000) begin
        $error("[TB] TIMEOUT waiting for VGA sample pixel (%0d,%0d).", SAMPLE_X, SAMPLE_Y);
        ctrl_errors = ctrl_errors + 1;
        break;
      end
    end

    // Final summary
    if ((mon_errors + ctrl_errors) == 0 && expected_count > 0) begin
      $display("\n[TB] PASS ?  Triangle raster, BRAM contents, and VGA output verified.\n");
    end else begin
      $display("\n[TB] FAIL ?  mon_errors=%0d ctrl_errors=%0d total=%0d expected_count=%0d wr_pulses=%0d\n",
               mon_errors, ctrl_errors, mon_errors + ctrl_errors, expected_count, wr_pulses);
    end

    $stop;
  end

endmodule

`default_nettype wire