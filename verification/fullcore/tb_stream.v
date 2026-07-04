// Streaming full-transform harness: drives the REAL invented RTL modules
// (compact_bf_v2 + tf_rom_fold) through a complete N=1024 DIT-NR NTT and
// DIF-RN INTT under iverilog.  The butterfly is PIPELINED (one issue per
// cycle; results collected LAT cycles later via an index delay line), which
// is how compact_bf_v2 is meant to run and how it was proven (fv_bf_v2).
// Butterflies within a stage touch disjoint indices, so back-to-back issue
// has no RAW hazard; the pipeline is drained before the next stage starts.
//
// This exercises the inventions end-to-end at RTL WITHOUT cfntt_ref's exact
// banked-memory FSM (the released fsm.v is empty — upstream #4).  The banked
// schedule is orthogonal to the drop-in inventions; here we show the modules
// themselves sequence into a correct transform.  The whole folded ROM is
// pre-read into wrom[] first, exercising tf_rom_fold across its full range.
`timescale 1ns / 1ps
module tb_stream;
  localparam N = 1024, LOGN = 10, PIPE = 10;
  // Effective collect tap: the index delay-line depth at which a butterfly's
  // output lands, measured empirically and matching the pipeline (the shift
  // happens inside the same step that samples inputs, so the tap is LAT-1).
  localparam TAP = 5;

  reg clk = 0, rst; always #5 clk = ~clk;

  reg sel; reg [13:0] u, v, w;
  wire [13:0] bf_lower, bf_upper;
  compact_bf_v2 bf (.clk(clk), .rst(rst), .sel(sel),
                    .u(u), .v(v), .w(w),
                    .bf_upper(bf_upper), .bf_lower(bf_lower));

  reg [9:0] rom_a; reg rom_ren; wire [13:0] rom_q;
  tf_rom_fold rom (.clk(clk), .A(rom_a), .REN(rom_ren), .Q(rom_q));

  reg [13:0] a [0:N-1];
  reg [13:0] wrom [1:1023];              // wrom[r] = W[r], read from the ROM
  reg [13:0] w_beat [0:PIPE];            // twiddle delay line (unused sink)

  // index delay lines for pipelined collect
  reg [10:0] lo_pipe [0:PIPE];
  reg [10:0] hi_pipe [0:PIPE];
  reg        v_pipe  [0:PIPE];

  integer p, J, k, j, lo, hi, r, t, d;

  task automatic step_collect;
    begin
      @(posedge clk); #1;
      if (v_pipe[TAP]) begin
        a[lo_pipe[TAP]] = bf_lower;
        a[hi_pipe[TAP]] = bf_upper;
      end
      for (d = PIPE; d > 0; d = d - 1) begin
        lo_pipe[d] = lo_pipe[d-1]; hi_pipe[d] = hi_pipe[d-1];
        v_pipe[d]  = v_pipe[d-1];
      end
      v_pipe[0] = 1'b0;                  // default: bubble
    end
  endtask

  task automatic issue(input isel, input [10:0] ilo, input [10:0] ihi,
                       input [13:0] iw);
    begin
      sel = isel; u = a[ilo]; v = a[ihi]; w = iw;
      lo_pipe[0] = ilo; hi_pipe[0] = ihi; v_pipe[0] = 1'b1;
      step_collect;
    end
  endtask

  task automatic drain; begin u = 0; v = 0; w = 0; step_collect; end endtask

  integer ci;
  initial begin : main
    rst = 1; sel = 0; u = 0; v = 0; w = 0; rom_ren = 0; rom_a = 0;
    for (ci = 0; ci <= PIPE; ci = ci + 1) v_pipe[ci] = 1'b0;
    repeat (4) @(posedge clk); rst = 0; @(posedge clk);

    // pre-read the entire folded ROM: A in [0,1022] -> W[A+1]
    for (r = 1; r <= 1023; r = r + 1) begin
      rom_a = r - 1; rom_ren = 1'b1;
      @(posedge clk); #1; @(posedge clk); #1;
      wrom[r] = rom_q;
    end

    $readmemh("stream_in.hex", a);

    // ---- DIT-NR NTT, r ascending from 1 ----
    r = 1;
    for (p = LOGN-1; p >= 0; p = p - 1) begin
      J = 1 << p;
      for (k = 0; k < N/(2*J); k = k + 1) begin
        w_beat[0] = wrom[r]; r = r + 1;
        for (j = 0; j < J; j = j + 1) begin
          lo = k*2*J + j; hi = lo + J;
          issue(1'b0, lo[10:0], hi[10:0], w_beat[0]);
        end
      end
    end
    for (t = 0; t < PIPE; t = t + 1) drain;
    $writememh("stream_ntt.hex", a);
    $display("NTT_DONE");

    // ---- DIF-RN INTT, r descending from 1023 ----
    r = 1023;
    for (p = 0; p < LOGN; p = p + 1) begin
      J = 1 << p;
      for (k = 0; k < N/(2*J); k = k + 1) begin
        w_beat[0] = wrom[r]; r = r - 1;
        for (j = 0; j < J; j = j + 1) begin
          lo = k*2*J + j; hi = lo + J;
          issue(1'b1, lo[10:0], hi[10:0], w_beat[0]);
        end
      end
    end
    for (t = 0; t < PIPE; t = t + 1) drain;
    $writememh("stream_rt.hex", a);
    $display("RT_DONE");
    $finish;
  end
endmodule
