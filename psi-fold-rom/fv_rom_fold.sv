// RTL equivalence of the psi-fold ROM (tf_rom_fold.v, 512 stored words +
// fold7) against the SHIPPED tf_ROM.v (1023 words), plus its port-protocol
// behaviour, with REN free:
//
//   load : a cycle with REN=1 loads both ROMs consistently — one cycle
//          later 9 * Q_new == Q_ref (mod q), since the fold ROM stores the
//          9^-1-scaled words for the CFNTT-KRED butterfly.
//   hold : a cycle with REN=0 leaves BOTH outputs unchanged (tf_ROM holds
//          by its case-without-default; the fold ROM holds base/upper).
//
// load-correct + hold-stable together give full equivalence for every REN
// sequence, not just REN tied high.
//
// Legal addresses are A < 1023 (assumed below): the shipped tf_ROM has no
// case entry for A == 1023 (it holds its previous word) while the fold ROM
// wraps its internal index to 0 — a divergence only on an address the
// hardware NEVER emits: ../verification/reference-fv/fv_agu.sby proves tf_address_generator
// keeps its address inside [0, 1023) in both modes.
module fv_rom_fold (
    input clk,
    input REN,
    input [9:0] A
);
  localparam [13:0] GQ = 14'd12289;

  wire [13:0] q_new, q_ref;
  tf_rom_fold dut (.clk(clk), .A(A), .REN(REN), .Q(q_new));
  tf_ROM gold (.clk(clk), .A(A), .REN(REN), .Q(q_ref));

  always @* assume (A < 10'd1023);

  reg [1:0] cnt = 0;
  always @(posedge clk) if (cnt < 3) cnt <= cnt + 1;

  reg [17:0] nine_new;
  always @(posedge clk) begin
    if (cnt >= 2 && $past(REN)) begin
      nine_new = {4'd0, q_new} * 18'd9;
      assert (nine_new % {4'd0, GQ} == {4'd0, q_ref});  // q_new == 9^-1 * q_ref
      assert (q_new < GQ);
    end
    if (cnt >= 2 && !$past(REN)) begin
      assert (q_new == $past(q_new));
      assert (q_ref == $past(q_ref));
    end
  end
endmodule
