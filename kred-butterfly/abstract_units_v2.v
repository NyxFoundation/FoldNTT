// Behavioural abstractions for compositional verification of compact_bf_v2
// (assume-guarantee; each justified by a dedicated RTL proof):
//   modular_mul_kred     == (9*A*B) mod q, latency 4   <- fv_kred.sby
//   modular_add          == (x+y) mod q                <- ../verification/reference-fv/fv_units.sby
//   modular_substraction == (x-y) mod q                <- ../verification/reference-fv/fv_units.sby
//   modular_half         == x*2^-1 mod q (op21 shape)  <- ../verification/reference-fv/fv_units.sby
//
// DOMAIN-FAITHFUL: the leaf proofs justify these models only for operands
// < q.  Outside that domain each model yields an unconstrained $anyseq
// value, so a composite proof can only pass if no leaf inside the asserted
// cone ever sees an unreduced operand — the assume-guarantee domain seam is
// discharged by the solver, not by a manual argument.  (Unconstrained
// initial register contents may drive leaves out of domain during pipeline
// flush; the harness assertions are guarded past the flush window, so that
// nondeterminism never reaches an assert.)

module modular_mul_kred #(parameter data_width = 14)(
    input clk, rst,
    input [data_width-1:0] A_in, B_in,
    output wire [data_width-1:0] P_out
    );
    parameter q = 14'd12289;
    reg [data_width-1:0] s1, s2, s3, s4;
    wire [31:0] p9 = {18'd0, A_in} * {18'd0, B_in} * 32'd9;
    (* anyseq *) wire [data_width-1:0] junk_mul;
    wire in_domain = (A_in < q) && (B_in < q);
    always @(posedge clk or posedge rst) begin
      if (rst) begin s1 <= 0; s2 <= 0; s3 <= 0; s4 <= 0; end
      else begin s1 <= in_domain ? p9 % q : junk_mul; s2 <= s1; s3 <= s2; s4 <= s3; end
    end
    assign P_out = s4;
endmodule

module modular_add #(parameter data_width = 14)(
    input [data_width-1:0] x_add, y_add,
    output [data_width-1:0] z_add
    );
    parameter M = 12289;
    wire [data_width:0] s = x_add + y_add;
    (* anyseq *) wire [data_width-1:0] junk_add;
    assign z_add = (x_add < M && y_add < M)
                   ? ((s >= M) ? s - M : s[data_width-1:0])
                   : junk_add;
endmodule

module modular_substraction #(parameter data_width = 14)(
    input [data_width-1:0] x_sub, y_sub,
    output [data_width-1:0] z_sub
    );
    parameter M = 12289;
    (* anyseq *) wire [data_width-1:0] junk_sub;
    assign z_sub = (x_sub < M && y_sub < M)
                   ? ((x_sub >= y_sub) ? x_sub - y_sub : (x_sub + M) - y_sub)
                   : junk_sub;
endmodule

module modular_half #(parameter data_width = 14)(
    input [data_width-1:0] x_half,
    output [data_width-1:0] y_half
    );
    (* anyseq *) wire [data_width-1:0] junk_half;
    assign y_half = (x_half < 14'd12289)
                    ? (x_half[0] ? (x_half >> 1) + 14'd6145 : (x_half >> 1))
                    : junk_half;
endmodule
