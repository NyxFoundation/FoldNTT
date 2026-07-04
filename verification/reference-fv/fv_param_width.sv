// Item 6 — parameterisation: the combinational modular units keep computing
// mod-q arithmetic when instantiated WIDER than the shipped data_width=14
// (the modulus M = 12289 is a hard constant in every module, so widening the
// datapath must not change results on reduced inputs).
//
// NOTE this is the only *runtime-meaningful* parameter in the radix-2 tree:
// q is hardcoded in every module (M, M_half, q0), N=1024 is burned into the
// address generators and the twiddle ROM — the paper's N/q scalability is
// achieved by regenerating code, not by parameters.  Documented in
// yosys/README.md; this harness proves the datapath-width dimension sound.
module fv_param_width (
    input clk,
    input [13:0] x,
    input [13:0] y
);
  `include "golden.vh"

  wire [15:0] add16, sub16;
  modular_add #(.data_width(16)) add_w (
      .x_add({2'b00, x}), .y_add({2'b00, y}), .z_add(add16));
  modular_substraction #(.data_width(16)) sub_w (
      .x_sub({2'b00, x}), .y_sub({2'b00, y}), .z_sub(sub16));

  always @* begin
    assume (x < GQ);
    assume (y < GQ);
  end

  always @(posedge clk) begin
    assert (add16 == {2'b00, gadd(x, y)});
    assert (sub16 == {2'b00, gsub(x, y)});
  end
endmodule
