// RECONSTRUCTED control FSM for cfntt_ref's top_poly_mul (the released
// fsm.v is empty — upstream issue #4).  Module is named `fsm` with the
// exact port list top_poly_mul.v instantiates, so the shipped top links
// against it unchanged.
//
// Schedule (derived from the shipped datapath's own timing):
//   issue at t:  address_generator (comb) -> conflict_free_memory_map
//   t+1:         registered bank/tf addresses at the ports
//   t+2:         bank Q + network_bf_in reg -> u,v at the butterfly;
//                tf_ROM Q -> w  (aligned)
//   t+8:         butterfly out (latency 6) + network_bf_out (sel via
//                shift_7) + write address (shift_7 of read address)
//   edge t+8->t+9: write commits (WEN sampled during t+8)
// Hence: ren covers [t0, t0+ISSUES], wen = issue delayed 8 cycles.
// Butterfly pairs within a stage are disjoint (in-place radix-2), so the
// only hazard is the stage boundary — DRAIN waits the pipeline out before
// the next stage starts.
//
// Modes (conf, chosen to match tf_address_generator's decode, which treats
// conf==3'b001/3'b100 as forward-NTT twiddle order):
//   conf = 3'b001 : forward NTT  (sel=0, stages p = 9 down to 0)
//   conf = 3'b010 : inverse NTT  (sel=1, stages p = 0 up to 9)
// done_flag[0] / done_flag[1] latch on completion; drop conf to 0 to clear.
module fsm (
    input clk,
    input rst,
    input [2:0] conf,
    output reg sel,
    output reg [8:0] k,
    output reg [8:0] i,
    output reg [3:0] p,
    output wire wen,
    output wire ren,
    output wire en,
    output reg [3:0] done_flag
    );

    localparam ST_IDLE  = 2'd0;
    localparam ST_RUN   = 2'd1;
    localparam ST_DRAIN = 2'd2;

    reg [1:0] state;
    reg dir;                       // 0: p descending (NTT), 1: ascending (INTT)
    reg issue;
    reg [8:0] pipe;                // issue delay line for ren/wen shaping
    reg [4:0] drain;

    wire [8:0] i_max = (9'd1 << p) - 9'd1;            // i < 2^p
    wire [8:0] k_max = (9'd1 << (4'd9 - p)) - 9'd1;   // k < 2^(9-p)
    wire last_stage = dir ? (p == 4'd9) : (p == 4'd0);

    assign en  = 1'b1;
    assign ren = issue | pipe[0];
    assign wen = pipe[7];

    always @(posedge clk or posedge rst) begin
      if (rst) begin
        state <= ST_IDLE; sel <= 1'b0; dir <= 1'b0;
        k <= 0; i <= 0; p <= 0;
        issue <= 1'b0; pipe <= 0; drain <= 0;
        done_flag <= 4'd0;
      end else begin
        pipe <= {pipe[7:0], issue};

        case (state)
          ST_IDLE: begin
            issue <= 1'b0;
            if (conf == 3'b001 && !done_flag[0]) begin
              sel <= 1'b0; dir <= 1'b0; p <= 4'd9;   // NTT: p = 9 .. 0
              k <= 0; i <= 0; issue <= 1'b1; state <= ST_RUN;
            end else if (conf == 3'b010 && !done_flag[1]) begin
              sel <= 1'b1; dir <= 1'b1; p <= 4'd0;   // INTT: p = 0 .. 9
              k <= 0; i <= 0; issue <= 1'b1; state <= ST_RUN;
            end else if (conf == 3'b000) begin
              done_flag <= 4'd0;                     // ack/clear
            end
          end

          ST_RUN: begin
            // one butterfly per cycle: i inner, k outer (the model's loops)
            if (i == i_max) begin
              i <= 0;
              if (k == k_max) begin
                k <= 0;
                issue <= 1'b0;                       // stage fully issued
                drain <= 5'd16; state <= ST_DRAIN;
              end else begin
                k <= k + 9'd1;
              end
            end else begin
              i <= i + 9'd1;
            end
          end

          ST_DRAIN: begin
            if (drain == 0) begin
              if (last_stage) begin
                done_flag[dir ? 1 : 0] <= 1'b1;
                state <= ST_IDLE;
              end else begin
                p <= dir ? (p + 4'd1) : (p - 4'd1);
                k <= 0; i <= 0; issue <= 1'b1; state <= ST_RUN;
              end
            end else begin
              drain <= drain - 5'd1;
            end
          end

          default: state <= ST_IDLE;
        endcase
      end
    end
endmodule
