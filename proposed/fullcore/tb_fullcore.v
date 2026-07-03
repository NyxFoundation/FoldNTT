// Full-core testbench: preload the banks, run NTT (conf=1) then INTT
// (conf=2), dump the banks after each.  Plusargs select hex file paths so
// the python driver owns data generation and checking.
`timescale 1ns / 1ps
module tb_fullcore;
  reg clk = 0, rst;
  reg [2:0] conf;
  wire [3:0] done_flag;

`ifdef V2
  top_poly_mul_v2 dut (.clk(clk), .rst(rst), .conf(conf), .done_flag(done_flag));
`else
  top_poly_mul dut (.clk(clk), .rst(rst), .conf(conf), .done_flag(done_flag));
`endif

  always #5 clk = ~clk;

  integer cyc = 0;
  always @(posedge clk) begin
    cyc = cyc + 1;
    if (cyc > 400000) begin $display("TIMEOUT"); $finish; end
  end

  reg [1023:0] f_b0_in, f_b1_in, f_b0_ntt, f_b1_ntt, f_b0_rt, f_b1_rt;

  initial begin
    if (!$value$plusargs("b0in=%s", f_b0_in)) f_b0_in = "bank0_in.hex";
    if (!$value$plusargs("b1in=%s", f_b1_in)) f_b1_in = "bank1_in.hex";
    if (!$value$plusargs("b0ntt=%s", f_b0_ntt)) f_b0_ntt = "bank0_ntt.hex";
    if (!$value$plusargs("b1ntt=%s", f_b1_ntt)) f_b1_ntt = "bank1_ntt.hex";
    if (!$value$plusargs("b0rt=%s", f_b0_rt)) f_b0_rt = "bank0_rt.hex";
    if (!$value$plusargs("b1rt=%s", f_b1_rt)) f_b1_rt = "bank1_rt.hex";

    rst = 1; conf = 3'b000;
    repeat (4) @(posedge clk);
    rst = 0;
    repeat (2) @(posedge clk);
    $readmemh(f_b0_in, dut.bank_0.bank);
    $readmemh(f_b1_in, dut.bank_1.bank);
    $display("DBG loaded bank0[0]=%h bank0[1]=%h bank1[0]=%h", dut.bank_0.bank[0], dut.bank_0.bank[1], dut.bank_1.bank[0]);

    conf = 3'b001;                       // forward NTT
    wait (done_flag[0] == 1'b1);
    repeat (4) @(posedge clk);
    $writememh(f_b0_ntt, dut.bank_0.bank);
    $writememh(f_b1_ntt, dut.bank_1.bank);
    $display("NTT_DONE cycles=%0d", cyc);

    conf = 3'b000;                       // clear
    repeat (4) @(posedge clk);
    conf = 3'b010;                       // inverse NTT
    wait (done_flag[1] == 1'b1);
    repeat (4) @(posedge clk);
    $writememh(f_b0_rt, dut.bank_0.bank);
    $writememh(f_b1_rt, dut.bank_1.bank);
    $display("RT_DONE cycles=%0d", cyc);
    $finish;
  end
endmodule
