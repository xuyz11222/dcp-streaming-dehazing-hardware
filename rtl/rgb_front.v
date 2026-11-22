`timescale 1ns/1ps
module rgb_front #(
    parameter NR = 8,
    parameter NG = 8,
    parameter NB = 8,
    parameter NY = 8,
    parameter QROUND = 1
)(
    input  wire [23:0] rgb888,
    output wire [NR+NG+NB-1:0] rgb_q,
    output wire [NY-1:0]       min_y
);
    function [7:0] quant;
        input [7:0] x;
        input integer n;
        integer m;
        begin
            m = (1 << n) - 1;
            if (n == 8) quant = x;
            else if (QROUND) quant = (x * m + 127) / 255;
            else quant = (x * m) / 255;
        end
    endfunction

    function [NY-1:0] to_y;
        input [7:0] x;
        input integer m;
        begin
            if (m == 0) to_y = 0;
            else to_y = (x * ((1 << NY) - 1) + m/2) / m;
        end
    endfunction

    wire [7:0]    rq8 = quant(rgb888[23:16], NR);
    wire [7:0]    gq8 = quant(rgb888[15:8],  NG);
    wire [7:0]    bq8 = quant(rgb888[7:0],   NB);
    wire [NR-1:0] rq = rq8[NR-1:0];
    wire [NG-1:0] gq = gq8[NG-1:0];
    wire [NB-1:0] bq = bq8[NB-1:0];
    wire [NY-1:0] ry = to_y(rq, (1 << NR) - 1);
    wire [NY-1:0] gy = to_y(gq, (1 << NG) - 1);
    wire [NY-1:0] by = to_y(bq, (1 << NB) - 1);
    wire [NY-1:0] rg = (ry < gy) ? ry : gy;
    wire [NY-1:0] my = (by < rg) ? by : rg;

    assign rgb_q = {rq, gq, bq};
    assign min_y = my;
endmodule
