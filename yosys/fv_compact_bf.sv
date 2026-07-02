// Item 1b — pipeline timing of the WHOLE butterfly (compact_bf.v), verified
// on the RTL with the real DFF / shift_4 delay chains (common_lib.v), inputs
// streaming EVERY cycle.  This is exactly what the z3 model abstracted away
// (delays -> identity): if any delay chain misaligned the operands, these
// assertions would fail with a counterexample trace.
//
//   sel=0 (NTT):  latency 6:  bf_lower = u + v*w,  bf_upper = u - v*w
//   sel=1 (INTT): latency 6:  bf_lower = u + v,    bf_upper = (v-u)*w
//     (NO per-stage halving — the released RTL omits op21; see
//      bug_intt_halving.py.  The assertions verify what the RTL computes.)
//
// sel is tied per top module (the phase is constant while data streams, as
// the phase-sequenced design intends) so yosys constant-folds the mode muxes
// and each SMT task carries only one mode's logic.  The latency bound (6) is
// independently confirmed structurally by audit.py (feed-forward pipeline,
// longest input->output register path == 6).
module fv_compact_bf_ntt (
    input clk,
    input [13:0] u,
    input [13:0] v,
    input [13:0] w
);
  `include "golden.vh"

  wire [13:0] bf_upper, bf_lower;
  compact_bf dut (
      .clk(clk), .rst(1'b0), .sel(1'b0),
      .u(u), .v(v), .w(w),
      .bf_upper(bf_upper), .bf_lower(bf_lower)
  );

  always @* begin
    assume (u < GQ);
    assume (v < GQ);
    assume (w < GQ);
  end

  reg [3:0] cnt = 0;
  always @(posedge clk) if (cnt < 15) cnt <= cnt + 1;

  reg [13:0] m6;
  always @(posedge clk) begin
    m6 = gmul($past(v, 6), $past(w, 6));
    if (cnt >= 7) begin  // DIT butterfly, latency 6
      assert (bf_lower == gadd($past(u, 6), m6));
      assert (bf_upper == gsub($past(u, 6), m6));
      assert (bf_lower < GQ);
      assert (bf_upper < GQ);
    end
  end
endmodule

module fv_compact_bf_intt (
    input clk,
    input [13:0] u,
    input [13:0] v,
    input [13:0] w
);
  `include "golden.vh"

  wire [13:0] bf_upper, bf_lower;
  compact_bf dut (
      .clk(clk), .rst(1'b0), .sel(1'b1),
      .u(u), .v(v), .w(w),
      .bf_upper(bf_upper), .bf_lower(bf_lower)
  );

  always @* begin
    assume (u < GQ);
    assume (v < GQ);
    assume (w < GQ);
  end

  reg [3:0] cnt = 0;
  always @(posedge clk) if (cnt < 15) cnt <= cnt + 1;

  always @(posedge clk) begin
    if (cnt >= 7) begin  // DIF butterfly (as released: no op21), latency 6
      assert (bf_lower == gadd($past(u, 6), $past(v, 6)));
      assert (bf_upper == gmul(gsub($past(v, 6), $past(u, 6)), $past(w, 6)));
      assert (bf_lower < GQ);
      assert (bf_upper < GQ);
    end
  end
endmodule
