`timescale 1ns/1ps
module dcp_stream_top #(
    parameter W = 384,
    parameter H = 384,
    parameter NR = 8,
    parameter NG = 8,
    parameter NB = 8,
    parameter NY = 8,
    parameter QROUND = 1,
    parameter OMEGA_Q = 0,
    parameter T0 = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        in_valid,
    input  wire [23:0] in_pixel,
    output wire        in_ready,
    output wire        out_valid,
    output wire [23:0] out_pixel,
    output wire        done,
    output wire [NY-1:0] A_dbg
);
    localparam OM_Q = (OMEGA_Q == 0) ? (95 * (1 << NY) + 50) / 100 : OMEGA_Q;
    localparam T_0  = (T0 == 0) ? (10 * ((1 << NY) - 1) + 50) / 100 : T0;

    wire [NR+NG+NB-1:0] rgb_q;
    wire [NY-1:0]       min_y;
    wire [NY-1:0]       win_blur, win_aux_ignore;
    wire [NR+NG+NB-1:0] win_aux;
    wire                win_v, win_done;
    wire [NY-1:0]       A_prev;
    wire                restart;
    wire                win_start = start | restart;

    rgb_front #(.NR(NR), .NG(NG), .NB(NB), .NY(NY), .QROUND(QROUND)) u_front (
        .rgb888(in_pixel),
        .rgb_q(rgb_q),
        .min_y(min_y)
    );

    win3x3_min #(.W(W), .H(H), .DW(NY), .AUXW(NR+NG+NB)) u_win (
        .clk(clk),
        .rst_n(rst_n),
        .start(win_start),
        .in_valid(in_valid),
        .in_data(min_y),
        .in_aux(rgb_q),
        .in_ready(in_ready),
        .out_valid(win_v),
        .out_blur(win_blur),
        .out_center(win_aux_ignore),
        .out_aux(win_aux),
        .done(win_done)
    );

    dcp_auto_a #(.W(W), .H(H), .NY(NY)) u_auto_a (
        .clk(clk),
        .rst_n(rst_n),
        .v(win_v),
        .dark(win_blur),
        .done(win_done),
        .A_prev(A_prev),
        .restart(restart)
    );

    dcp_calc #(
        .NR(NR), .NG(NG), .NB(NB), .NY(NY),
        .OMEGA_Q(OM_Q), .T0(T_0)
    ) u_calc (
        .rgb(win_aux),
        .dark(win_blur),
        .A_prev(A_prev),
        .out(out_pixel)
    );

    assign out_valid = win_v;
    assign done = win_done;
    assign A_dbg = A_prev;
endmodule
