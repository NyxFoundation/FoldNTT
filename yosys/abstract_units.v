// Behavioural abstractions of the modular units for COMPOSITIONAL
// verification of compact_bf (assume-guarantee):
//
//   modular_mul          == (A*B) mod q, latency 4   <- proven of the RTL in
//                                                       fv_modular_mul.sby
//   modular_add          == (x+y) mod q, combinational  <- fv_units.sby
//   modular_substraction == (x-y) mod q, combinational  <- fv_units.sby
//
// Each abstraction is justified by a dedicated SymbiYosys proof that the
// real RTL module is equivalent to exactly this behaviour.  Substituting
// them when elaborating compact_bf removes every hard arithmetic cone from
// the butterfly obligation, leaving muxes, routing and the delay chains —
// and lets the golden expressions hash structurally equal to the DUT's, so
// the SMT tasks close in seconds instead of re-bit-blasting multipliers.

module modular_mul #(parameter data_width = 14)(
    input clk, rst,
    input [data_width-1:0] A_in, B_in,
    output wire [data_width-1:0] P_out
    );

    parameter q = 14'd12289;

    reg [data_width-1:0] s1, s2, s3, s4;
    wire [data_width*2-1:0] prod = A_in * B_in;

    always @(posedge clk or posedge rst) begin
      if (rst) begin
        s1 <= 0; s2 <= 0; s3 <= 0; s4 <= 0;
      end else begin
        s1 <= prod % q;
        s2 <= s1;
        s3 <= s2;
        s4 <= s3;
      end
    end

    assign P_out = s4;
endmodule

module modular_add #(parameter data_width = 14)(
    input [data_width-1:0] x_add,
    input [data_width-1:0] y_add,
    output [data_width-1:0] z_add
    );

    parameter M = 12289;
    wire [data_width:0] s = x_add + y_add;
    assign z_add = (s >= M) ? s - M : s[data_width-1:0];
endmodule

module modular_substraction #(parameter data_width = 14)(
    input [data_width-1:0] x_sub,
    input [data_width-1:0] y_sub,
    output [data_width-1:0] z_sub
    );

    parameter M = 12289;
    assign z_sub = (x_sub >= y_sub) ? x_sub - y_sub
                                    : (x_sub + M) - y_sub;
endmodule
