//------------------------------------------------------------------------------
// File       : gpu_cmd_top_tb.sv
// Author     : Nelson Rodriguez-Ortiz (assisted with ChatGPT)
// Description: SystemVerilog testbench for the gpu_cmd_top module.
//
//              This testbench verifies the command path from the write-back
//              domain into the GPU domain through the command FIFO and command
//              decode/output logic.
//
//              Main verification goals:
//              1. Drive command words into gpu_cmd_top from the WB clock domain.
//              2. Verify commands are correctly transferred into the GPU clock
//                 domain.
//              3. Check that cmd_valid asserts for each expected command.
//              4. Verify that cmd_word matches the pushed command word.
//              5. Verify that cmd_opcode matches the expected opcode field.
//
// Notes      :
//              - Uses separate WB and GPU clocks to exercise clock domain
//                crossing behavior.
//              - Uses clocking blocks to reduce TB/DUT race conditions.
//              - Includes a simple scoreboard queue for end-to-end checking.
//
//------------------------------------------------------------------------------

module gpu_cmd_top_tb;

  timeunit 1ns;
  timeprecision 1ps;

  localparam int WIDTH = 32;
  localparam int DEPTH = 64;

  // -----------------------------------------
  // Clocks / resets
  // -----------------------------------------
  logic wb_clk, gpu_clk;
  logic wb_rst, gpu_rst;

  initial wb_clk = 0;
  always #5 wb_clk = ~wb_clk;

  initial gpu_clk = 0;
  always #7 gpu_clk = ~gpu_clk;

  // -----------------------------------------
  // DUT I/O
  // -----------------------------------------
  logic             cmd_push;
  logic [31:0]      cmd_wdata;
  logic             cmd_full;

  logic             prim_mode_en_wb;

  logic             cmd_valid;
  logic [31:0]      cmd_word;
  logic [3:0]       cmd_opcode;

  // -----------------------------------------
  // DUT
  // -----------------------------------------
  gpu_cmd_top #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .wb_clk           (wb_clk),
    .wb_rst           (wb_rst),
    .cmd_push         (cmd_push),
    .cmd_wdata        (cmd_wdata),
    .cmd_full         (cmd_full),

    .gpu_clk          (gpu_clk),
    .gpu_rst          (gpu_rst),

    .prim_mode_en_wb  (prim_mode_en_wb),

    .cmd_valid        (cmd_valid),
    .cmd_word         (cmd_word),
    .cmd_opcode       (cmd_opcode)
  );

  // -----------------------------------------
  // Clocking blocks (avoid TB/DUT races)
  // -----------------------------------------
  clocking cb_wb @(posedge wb_clk);
    output cmd_push, cmd_wdata;
    input  cmd_full;
  endclocking

  // Sample GPU outputs *after* DUT NBA updates
  clocking cb_gpu @(posedge gpu_clk);
    default input #1step;
    input cmd_valid, cmd_word, cmd_opcode;
  endclocking

  // -----------------------------------------
  // Scoreboard
  // -----------------------------------------
  logic [31:0] exp_q[$];

  // -----------------------------------------
  // Push task (WB domain)
  // -----------------------------------------
  task automatic push_cmd(input logic [31:0] word);
    begin
      // Wait for a WB edge
      @cb_wb;

      if (cb_wb.cmd_full) begin
        $error("Attempted push while FIFO full");
      end

      cb_wb.cmd_wdata <= word;
      cb_wb.cmd_push  <= 1'b1;

      // Hold for 1 cycle
      @cb_wb;
      cb_wb.cmd_push <= 1'b0;

      exp_q.push_back(word);
    end
  endtask

  // -----------------------------------------
  // GPU-side checker (samples via cb_gpu)
  // -----------------------------------------
  always @(cb_gpu) begin
    if (!gpu_rst && cb_gpu.cmd_valid) begin
      if (exp_q.size() == 0) begin
        $error("[%0t] Received cmd_valid but scoreboard empty", $time);
      end else begin
        logic [31:0] expected;
        expected = exp_q.pop_front();

        if (cb_gpu.cmd_word !== expected) begin
          $error("[%0t] CMD WORD MISMATCH: got 0x%08h expected 0x%08h",
                 $time, cb_gpu.cmd_word, expected);
        end

        if (cb_gpu.cmd_opcode !== expected[31:28]) begin
          $error("[%0t] OPCODE MISMATCH: got 0x%0h expected 0x%0h",
                 $time, cb_gpu.cmd_opcode, expected[31:28]);
        end

        $display("[%0t] CMD OK: word=0x%08h opcode=0x%0h",
                 $time, cb_gpu.cmd_word, cb_gpu.cmd_opcode);
      end
    end
  end

  // -----------------------------------------
  // Stimulus
  // -----------------------------------------
  initial begin
    // Init
    wb_rst          = 1;
    gpu_rst         = 1;
    cmd_push        = 0;
    cmd_wdata       = 0;
    prim_mode_en_wb = 0;

    // Release resets at different times
    #20 wb_rst  = 0;
    #15 gpu_rst = 0;

    // Enable prim mode
    #30 prim_mode_en_wb = 1;

    // Give sync time
    repeat (5) @(posedge gpu_clk);

    $display("\n--- Sending Commands ---");

    // Known commands
    push_cmd(32'h1000_0001);
    push_cmd(32'h2000_00AA);
    push_cmd(32'hA123_4567);
    push_cmd(32'hF000_0000);

    // Wait long enough for drain
    repeat (200) @(posedge gpu_clk);

    if (exp_q.size() != 0) begin
      $error("Simulation ended but scoreboard not empty! Remaining=%0d", exp_q.size());
    end else begin
      $display("\nAll commands verified successfully.");
    end

    $finish;
  end

endmodule
