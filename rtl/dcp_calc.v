`timescale 1ns/1ps
module dcp_calc #(
    parameter NR = 8,
    parameter NG = 8,
    parameter NB = 8,
    parameter NY = 8,
    parameter OMEGA_Q = 243,
    parameter T0 = 26
)(
    input  wire [NR+NG+NB-1:0] rgb,
    input  wire [NY-1:0] dark,
    input  wire [NY-1:0] A_prev,
    output reg  [23:0]   out
);
    localparam R_MAX = (1 << NR) - 1;
    localparam G_MAX = (1 << NG) - 1;
    localparam B_MAX = (1 << NB) - 1;
    localparam Y_MAX = (1 << NY) - 1;
    localparam Y_ONE = 1 << NY;

    integer cr, cg, cb, a, ar, ag, ab, norm, t, num, jr, jg, jb;
    integer r8, g8, b8;

    always @(*) begin
        cr = rgb[NR+NG+NB-1:NG+NB];
        cg = rgb[NG+NB-1:NB];
        cb = rgb[NB-1:0];

        a = 1;
        ar = 0; ag = 0; ab = 0;
        norm = 0; t = Y_MAX; num = 0;
        jr = cr; jg = cg; jb = cb;

        if (A_prev != 0) begin
            a = A_prev;
            ar = (a * R_MAX + Y_MAX/2) / Y_MAX;
            ag = (a * G_MAX + Y_MAX/2) / Y_MAX;
            ab = (a * B_MAX + Y_MAX/2) / Y_MAX;

            norm = (dark * Y_MAX + a/2) / a;
            if (norm > Y_MAX) norm = Y_MAX;
            t = Y_MAX - (OMEGA_Q * norm) / Y_ONE;
            if (t < T0) t = T0;

            num = (cr - ar) * Y_MAX;
            jr = num / t + ar;
            if (jr < 0) jr = 0;
            if (jr > R_MAX) jr = R_MAX;
            num = (cg - ag) * Y_MAX;
            jg = num / t + ag;
            if (jg < 0) jg = 0;
            if (jg > G_MAX) jg = G_MAX;
            num = (cb - ab) * Y_MAX;
            jb = num / t + ab;
            if (jb < 0) jb = 0;
            if (jb > B_MAX) jb = B_MAX;
        end

        r8 = (jr * 255 + R_MAX/2) / R_MAX;
        g8 = (jg * 255 + G_MAX/2) / G_MAX;
        b8 = (jb * 255 + B_MAX/2) / B_MAX;
        out = {r8[7:0], g8[7:0], b8[7:0]};
    end
endmodule
