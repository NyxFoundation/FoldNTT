// Simulation-only stubs for Xilinx primitives used in the board wrapper.
// NOT for synthesis (synth_xilinx provides the real cells).
`timescale 1ns/1ps
module BUFG (input I, output O); assign O = I; endmodule
