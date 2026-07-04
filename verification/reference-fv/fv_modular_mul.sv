// Item 1a — pipeline timing + function of modular_mul.v, verified ON THE RTL
// (no hand transcription): with reduced inputs streaming EVERY cycle,
// P_out at time t equals (A_in * B_in) mod q sampled 4 cycles earlier.
//
// The initial register state is UNCONSTRAINED (symbolic) and the assertions
// only look back 4 cycles, so a BMC of depth > guard+4 covers every window
// of every execution — it is a complete proof, and `prove` (k-induction)
// closes it unboundedly as well.
module fv_modular_mul (
    input clk,
    input [13:0] A,
    input [13:0] B
);
  `include "golden.vh"

  wire [13:0] P;
  modular_mul dut (.clk(clk), .rst(1'b0), .A_in(A), .B_in(B), .P_out(P));

  // inputs are reduced every cycle (guaranteed upstream: every producer in
  // the design is a modular unit proven to emit < q)
  always @* begin
    assume (A < GQ);
    assume (B < GQ);
  end

  reg [3:0] cnt = 0;
  always @(posedge clk) if (cnt < 15) cnt <= cnt + 1;

  always @(posedge clk) begin
    if (cnt >= 5) begin
      assert (P == gmul($past(A, 4), $past(B, 4)));  // latency-4 product mod q
      assert (P < GQ);                               // output stays reduced
    end
  end
endmodule
