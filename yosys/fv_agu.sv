// Items 3 (static part) & 8 (access-pattern data-independence, together with
// audit.py) — the address-generation / bank-mapping RTL verified directly
// (this re-proves on the RTL what verify_radix2.py proved on a z3
// transcription, closing the transcription gap for F/E/G):
//
//   address_generator.v      operand-pair structure, no overflow, injectivity
//   conflict_free_memory_map.v  bank = parity, offset = addr>>1, banks differ
//   tf_address_generator.v   twiddle address == model r-counter - 1, in range
//
// Under the FSM ranges (k < 2^(9-p), i < 2^p — the model's loop bounds).
module fv_agu (
    input clk,
    input [8:0] k,
    input [8:0] i,
    input [3:0] p,
    input [8:0] k2,
    input [8:0] i2,
    input [2:0] conf
);
  wire [9:0] a0, a1, a0_b, a1_b;
  address_generator gen (.k(k), .i(i), .p(p),
                         .old_address_0(a0), .old_address_1(a1));
  address_generator gen_b (.k(k2), .i(i2), .p(p),
                           .old_address_0(a0_b), .old_address_1(a1_b));

  wire [8:0] na0, na1;
  wire bank0, bank1;
  conflict_free_memory_map map (
      .clk(clk), .rst(1'b0),
      .old_address_0(a0), .old_address_1(a1),
      .new_address_0(na0), .new_address_1(na1),
      .bank_number_0(bank0), .bank_number_1(bank1)
  );

  wire [9:0] tf_addr;
  tf_address_generator tfgen (.clk(clk), .rst(1'b0),
                              .conf(conf), .k(k), .p(p), .tf_address(tf_addr));

  // FSM ranges for stage p (the model's loop bounds)
  always @* begin
    assume (p <= 4'd9);
    assume ({1'b0, k} < (10'd1 << (4'd9 - p)));
    assume ({1'b0, i} < (10'd1 << p));
    assume ({1'b0, k2} < (10'd1 << (4'd9 - p)));
    assume ({1'b0, i2} < (10'd1 << p));
  end

  // ---- address_generator.v: combinational properties ----------------------
  wire [19:0] wide = ({11'd0, k} << (p + 1)) + {11'd0, i};
  always @* begin
    assert (wide < 20'd1024);                    // no 10-bit overflow
    assert (a0 == wide[9:0]);                    // the RTL shift-add formula
    assert (((a0 >> p) & 10'd1) == 10'd0);       // operand 0 has bit p = 0
    assert (a1 == (a0 | (10'd1 << p)));          // partner at stride 2^p
    assert ((^a0) != (^a1));                     // different parity => banks
    // injectivity: each stage enumerates every butterfly pair exactly once
    if (a0_b == a0) assert (k2 == k && i2 == i);
  end

  // ---- conflict_free_memory_map.v: registered outputs (1-cycle latency) ---
  reg [3:0] cnt = 0;
  always @(posedge clk) if (cnt < 15) cnt <= cnt + 1;

  always @(posedge clk) begin
    if (cnt >= 2) begin
      assert (bank0 == (^$past(a0)));            // bank = parity of address
      assert (bank1 == (^$past(a1)));
      assert (bank0 != bank1);                   // conflict-free
      assert (na0 == $past(a0) >> 1);            // offset = address >> 1
      assert (na1 == $past(a1) >> 1);
    end
  end

  // ---- tf_address_generator.v: twiddle address == model r-counter - 1 -----
  reg [3:0] pp;
  reg [9:0] kk;
  reg ntt_mode;
  always @(posedge clk) begin
    pp = $past(p);
    kk = {1'b0, $past(k)};
    ntt_mode = ($past(conf) == 3'b001) || ($past(conf) == 3'b100);
    if (cnt >= 2) begin
      assert (tf_addr == (ntt_mode
          ? ((10'd1 << (4'd9 - pp)) - 10'd1) + kk    // DIT r - 1
          : ((10'd2 << (4'd9 - pp)) - 10'd2) - kk)); // DIF r - 1
      assert (tf_addr < 10'd1023);               // inside the 1023-deep ROM
    end
  end
endmodule
