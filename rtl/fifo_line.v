`timescale 1ns/1ps
// FWFT line-delay FIFO (behavioral, for simulation only).
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
    localparam CW = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    reg [DW-1:0] mem [0:DEPTH-1];
    reg [CW-1:0] wp, rp;
    reg [CW:0]   cnt;

    assign dout  = mem[rp];
    assign empty = (cnt == 0);
    assign full  = (cnt == DEPTH);

    wire do_wr = wr_en && !full  && !clear;
    wire do_rd = rd_en && !empty && !clear;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= 0; rp <= 0; cnt <= 0;
        end else if (clear) begin
            wp <= 0; rp <= 0; cnt <= 0;
        end else begin
            if (do_wr) begin
                mem[wp] <= din;
                wp <= (wp == DEPTH-1) ? {CW{1'b0}} : wp + 1'b1;
            end
            if (do_rd) begin
                rp <= (rp == DEPTH-1) ? {CW{1'b0}} : rp + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10: cnt <= cnt + 1'b1;
                2'b01: cnt <= cnt - 1'b1;
                default: cnt <= cnt;
            endcase
        end
    end
endmodule
