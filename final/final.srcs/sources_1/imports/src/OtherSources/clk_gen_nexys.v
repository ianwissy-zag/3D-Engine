// SPDX-License-Identifier: Apache-2.0
// Copyright 2019 Western Digital Corporation or its affiliates.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//********************************************************************************
// $Id$
//
// Function: VeeRwolf Basys3 clock generation
// Comments:
//
//********************************************************************************

module clk_gen_nexys
  (input  wire i_clk,
   input  wire i_rst,
   output wire o_clk_core,
   output wire o_clk_vga,
   output wire o_clk_gpu,
   output reg o_rst_core,
   output reg o_rst_vga);

   wire   clkfb;
   wire   locked;
   reg 	  locked_core_r;
   reg    locked_vga_r;
   wire clk_core_unbuffered;
   wire clk_vga_unbuffered;
   wire clk_gpu_unbuffered;

   PLLE2_BASE
     #(.BANDWIDTH("OPTIMIZED"),
       .CLKFBOUT_MULT(8),
       .CLKIN1_PERIOD(10.0), //100MHz
       .CLKOUT0_DIVIDE(64), // Main clock 12.5MHz
       .CLKOUT1_DIVIDE(32), // Secondary clock 25MHz
       .CLKOUT2_DIVIDE(8),
       .DIVCLK_DIVIDE(1),
       .STARTUP_WAIT("FALSE"))
   PLLE2_BASE_inst(
      .CLKOUT0(clk_core_unbuffered), // Raw output
      .CLKOUT1(clk_vga_unbuffered),  // Raw output
      .CLKOUT2(clk_gpu_unbuffered),
      .CLKOUT3(),
      .CLKOUT4(),
      .CLKOUT5(),
      .CLKFBOUT(clkfb),
      .LOCKED(locked),
      .CLKIN1(i_clk),
      .PWRDWN(1'b0),
      .RST(i_rst),
      .CLKFBIN(clkfb));

   always @(posedge o_clk_core) begin
      locked_core_r <= locked;
      o_rst_core <= !locked_core_r;
   end
   
   always @(posedge o_clk_vga) begin
      locked_vga_r <= locked;
      o_rst_vga <= !locked_vga_r;
   end

// Instantiate the buffers to move the signals to the global clock network
   BUFG clk_core_bufg (.I(clk_core_unbuffered), .O(o_clk_core));
   BUFG clk_vga_bufg  (.I(clk_vga_unbuffered),  .O(o_clk_vga));
   BUFG clk_gpu_bufg  (.I(clk_gpu_unbuffered),  .O(o_clk_gpu));
endmodule
