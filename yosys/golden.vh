// Golden (specification-side) mod-q operators, shared by the harnesses.
// gmul uses % by the CONSTANT q — the SMT encoding (bvurem by a constant)
// is well within reach of the solvers for these bit widths.

localparam [13:0] GQ = 14'd12289;

function [13:0] gadd(input [13:0] a, input [13:0] b);
  reg [14:0] s;
  begin
    s = a + b;
    gadd = (s >= GQ) ? s - GQ : s[13:0];
  end
endfunction

function [13:0] gsub(input [13:0] a, input [13:0] b);
  gsub = (a >= b) ? a - b : (a + GQ) - b;
endfunction

function [13:0] gmul(input [13:0] a, input [13:0] b);
  reg [27:0] p;
  begin
    p = a * b;
    gmul = p % GQ;
  end
endfunction
