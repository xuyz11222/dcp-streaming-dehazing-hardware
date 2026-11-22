// Black-box FIFO for synthesis / ABC statistics (not counted as regs/LUTs).
(* blackbox *)
module fifo_line #(
    parameter DEPTH = 8,
    parameter DW    = 57
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          clear,
    input  wire          wr_en,
    input  wire          rd_en,
    input  wire [DW-1:0] din,
    output wire [DW-1:0] dout,
    output wire          empty,
    output wire          full
);
endmodule
