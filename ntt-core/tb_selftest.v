`timescale 1ns/1ps
module tb_selftest;
  reg clk=0; always #5 clk=~clk;
  reg btn=0; wire [15:0] led;
  basys3_ntt_selftest dut(.clk(clk), .btn_start(btn), .led(led));
  initial begin
    wait(led[0]==1'b1);         // done
    #1;
    $display("done=%b PASS=%b FAIL=%b miss=%0d", led[0], led[1], led[2], led[15:6]);
    if (led[1] && !led[2]) $display("BASYS3 SELFTEST SIM: PASS");
    else                   $display("BASYS3 SELFTEST SIM: FAIL");
    $finish;
  end
  initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
