// RTL proof of the proposed modular_mul_kred: with reduced inputs streaming
// every cycle, P_out at time t == (9 * A * B) mod q sampled 4 cycles
// earlier, and the output stays < q.  Also: rst forces P_out to 0.
//
// (Same complete-BMC structure as ../yosys/fv_modular_mul.sv: time-local
// assertions + unconstrained initial state => depth guard+4+1 covers every
// window of every execution.)
module fv_kred (
    input clk,
    input [13:0] A,
    input [13:0] B
);
  localparam [13:0] GQ = 14'd12289;

  wire [13:0] P;
  modular_mul_kred dut (.clk(clk), .rst(1'b0), .A_in(A), .B_in(B), .P_out(P));

  always @* begin
    assume (A < GQ);
    assume (B < GQ);
  end

  reg [3:0] cnt = 0;
  always @(posedge clk) if (cnt < 15) cnt <= cnt + 1;

  reg [31:0] p9;
  always @(posedge clk) begin
    if (cnt >= 5) begin
      p9 = {18'd0, $past(A, 4)} * {18'd0, $past(B, 4)} * 32'd9;
      assert (P == p9 % GQ);      // latency-4, == 9AB mod q
      assert (P < GQ);            // output stays reduced
    end
  end
endmodule

// rst behaviour, from ANY state (own top, tiny)
module fv_kred_rst (
    input clk,
    input rst,
    input [13:0] A,
    input [13:0] B
);
  wire [13:0] P;
  modular_mul_kred dut (.clk(clk), .rst(rst), .A_in(A), .B_in(B), .P_out(P));
  always @* if (rst) assert (P == 14'd0);
endmodule
