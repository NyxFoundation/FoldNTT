// Functional round-trip test for ntt_core: load x, run NTT then INTT, and
// check INTT(NTT(x)) == 2^10 * x (mod q) for every coefficient.  This is the
// whole-core, banked-memory, own-FSM correctness the reconstructed CFNTT FSM
// never reached — here it must hold by construction.
`timescale 1ns / 1ps
module tb_ntt_core;
    localparam DW = 14, N = 1024, AW = 10, Q = 12289;

    reg clk = 0, rst;
    always #5 clk = ~clk;

    reg          start, mode, h_we;
    reg  [AW-1:0] h_addr;
    reg  [DW-1:0] h_din;
    wire [DW-1:0] h_dout;
    wire         busy, done;

    ntt_core #(.BF_LAT(8)) dut (
        .clk(clk), .rst(rst), .start(start), .mode(mode),
        .busy(busy), .done(done),
        .h_we(h_we), .h_addr(h_addr), .h_din(h_din), .h_dout(h_dout));

    reg [DW-1:0] x [0:N-1];      // reference input
    integer i, errors;

    task automatic load_mem;
        integer m;
        begin
            for (m = 0; m < N; m = m + 1) begin
                @(posedge clk); #1;
                h_we = 1'b1; h_addr = m[AW-1:0]; h_din = x[m];
            end
            @(posedge clk); #1; h_we = 1'b0;
        end
    endtask

    task automatic run(input md);
        begin
            @(posedge clk); #1; mode = md; start = 1'b1;
            @(posedge clk); #1; start = 1'b0;
            wait (done == 1'b1);
            @(posedge clk); #1;
        end
    endtask

    // read mem[idx] through the host port (registered, 1-cycle latency)
    task automatic rd(input [AW-1:0] idx, output [DW-1:0] val);
        begin
            @(posedge clk); #1; h_addr = idx; h_we = 1'b0;
            @(posedge clk); #1;                 // a_q <= mem[idx]
            val = h_dout;
        end
    endtask

    reg [DW-1:0] got; reg [31:0] want;
    initial begin : main
        rst = 1; start = 0; mode = 0; h_we = 0; h_addr = 0; h_din = 0;
        errors = 0;
        // a simple deterministic, non-trivial input
        for (i = 0; i < N; i = i + 1) x[i] = (i*7 + 1) % Q;

        repeat (5) @(posedge clk); #1; rst = 0;

        // publish the exact input so the golden streaming harness can run it
        begin : dumpin
            integer f, m;
            f = $fopen("newcore/nc_in.hex", "w");
            for (m = 0; m < N; m = m + 1) $fdisplay(f, "%h", x[m]);
            $fclose(f);
        end

        load_mem;
        run(1'b0);      // NTT
        // dump the post-NTT memory for cross-validation vs tb_stream's golden
        begin : dumpntt
            integer f; reg [DW-1:0] vv;
            f = $fopen("newcore/nc_ntt.hex", "w");
            for (i = 0; i < N; i = i + 1) begin rd(i[AW-1:0], vv); $fdisplay(f, "%h", vv); end
            $fclose(f);
        end
        run(1'b1);      // INTT
        $display("transform done, checking round-trip INTT(NTT(x)) == x (fixed core) ...");

        for (i = 0; i < N; i = i + 1) begin
            rd(i[AW-1:0], got);
            want = x[i];  // compact_bf_v2 is the bug-FIXED butterfly: 1/N restored
            if (got !== want[DW-1:0]) begin
                if (errors < 12)
                    $display("  MISMATCH i=%0d got=%0d want=%0d (x=%0d)",
                             i, got, want, x[i]);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("NTT_CORE ROUND-TRIP PASS (N=%0d)", N);
        else             $display("NTT_CORE ROUND-TRIP FAIL: %0d/%0d mismatches",
                                  errors, N);
        $finish;
    end

    // safety timeout
    initial begin #20000000; $display("TIMEOUT"); $finish; end
endmodule
