// Justification of the combinational abstractions in abstract_units.v:
// the REAL modular_add.v / modular_substraction.v / modular_half.v are
// equivalent to the golden mod-q behaviour on reduced inputs — proven on
// the RTL, over the full input domain (these are the yosys-side twins of
// z3 checks A/B/C, closing the transcription gap on the RTL itself).
// (modular_mul's abstraction is justified separately by fv_modular_mul.sby.)
module fv_units (
    input clk,
    input [13:0] x,
    input [13:0] y
);
  `include "golden.vh"

  wire [13:0] z_add, z_sub, y_half;
  modular_add add_dut (.x_add(x), .y_add(y), .z_add(z_add));
  modular_substraction sub_dut (.x_sub(x), .y_sub(y), .z_sub(z_sub));
  modular_half #(.data_width(14)) half_dut (.x_half(x), .y_half(y_half));

  // 2^-1 mod q = (q+1)/2 = 6145; x/2 mod q as a function
  function [13:0] ghalf(input [13:0] a);
    ghalf = (a[0] == 1'b0) ? (a >> 1) : ((a >> 1) + 14'd6145) % GQ;
  endfunction

  always @* begin
    assume (x < GQ);
    assume (y < GQ);
  end

  always @(posedge clk) begin
    assert (z_add == gadd(x, y));
    assert (z_sub == gsub(x, y));
    assert (y_half == ghalf(x));
    assert (z_add < GQ);
    assert (z_sub < GQ);
    assert (y_half < GQ);
  end
endmodule
