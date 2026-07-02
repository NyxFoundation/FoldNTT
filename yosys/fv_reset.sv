// Item 4a — asynchronous reset: while rst is asserted, both butterfly
// outputs are 0 in either mode, from ANY (symbolic) register state.
//
// Item 4b (power-up X robustness) is proven STRUCTURALLY in audit.py: the
// flattened compact_bf tree is a feed-forward pipeline (the FF dependency
// graph is acyclic) whose longest input->output register path is exactly 6,
// so every register is overwritten from primary inputs within 6 cycles and
// no power-up X can influence outputs after the pipeline has flushed.
module fv_reset (
    input clk,
    input rst,
    input sel,
    input [13:0] u,
    input [13:0] v,
    input [13:0] w
);
  wire [13:0] r_upper, r_lower;
  compact_bf dut_rst (
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
