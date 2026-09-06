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

  // Cycle counter, advanced on the posedge; all testbench-side changes
  // (reset release, conf, dumps, reports, and the cycle-count samples)
  // happen on NEGEDGES so they never race the DUT's posedge sampling or the
  // counter's own increment.  A transform's cycle count is the number of
  // clock periods from the launch edge (the first posedge at which the FSM
  // samples conf, i.e. cyc+1 at the negedge where conf is raised) to the
  // posedge at which done_flag rises: launch-to-done elapsed clocks, no
  // startup or dump overhead.
  integer cyc = 0, t_launch = 0;
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
    repeat (4) @(negedge clk);
    rst = 0;
    repeat (2) @(negedge clk);
    // Load on a NEGEDGE: data_bank refreshes bank[A1] <= bank[A1] on every
    // posedge, so a $readmemh in a posedge time step races with that
    // nonblocking self-write (address 0 of both banks came back X).
    $readmemh(f_b0_in, dut.bank_0.bank, 0, 511);
    $readmemh(f_b1_in, dut.bank_1.bank, 0, 511);
    conf = 3'b001;                       // forward NTT (hold until done)
    t_launch = cyc + 1;                  // launch edge = next posedge; sampled at a negedge, no race
    wait (done_flag[0] == 1'b1);
    @(negedge clk);
    $display("NTT_CYCLES=%0d", cyc - t_launch);
    repeat (4) @(negedge clk);
    $writememh(f_b0_ntt, dut.bank_0.bank, 0, 511);
    $writememh(f_b1_ntt, dut.bank_1.bank, 0, 511);
    $display("NTT_DONE");
    conf = 3'b000;                       // clear
    repeat (4) @(negedge clk);
    conf = 3'b010;                       // inverse NTT (hold until done)
    t_launch = cyc + 1;                  // launch edge = next posedge; sampled at a negedge, no race
    wait (done_flag[1] == 1'b1);
    @(negedge clk);
    $display("INTT_CYCLES=%0d", cyc - t_launch);
    repeat (4) @(negedge clk);
    $writememh(f_b0_rt, dut.bank_0.bank, 0, 511);
    $writememh(f_b1_rt, dut.bank_1.bank, 0, 511);
    $display("RT_DONE");
    $finish;
  end
endmodule
