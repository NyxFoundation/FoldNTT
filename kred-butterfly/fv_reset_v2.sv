// Reset behaviour of the PROPOSED butterfly, with the REAL leaf units
// (modular_mul_kred included): while rst is asserted, both outputs are 0
// in either mode, from ANY (symbolic) register state — the async-reset
// analogue of ../verification/reference-fv/fv_reset.sv for compact_bf_v2.
// (Power-up X robustness is the per-mode feed-forward audit in audit_v2.py.)
module fv_reset_v2 (
    input clk,
    input rst,
    input sel,
    input [13:0] u,
    input [13:0] v,
    input [13:0] w
);
  wire [13:0] r_upper, r_lower;
  compact_bf_v2 dut (
      .clk(clk), .rst(rst), .sel(sel),
      .u(u), .v(v), .w(w),
      .bf_upper(r_upper), .bf_lower(r_lower)
  );

  always @* begin
    if (rst) begin
      assert (r_upper == 14'd0);
      assert (r_lower == 14'd0);
    end
  end
endmodule
