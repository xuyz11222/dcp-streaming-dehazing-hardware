`timescale 1ns/1ps
module dcp_auto_a #(
    parameter W = 384,
    parameter H = 384,
    parameter NY = 8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          v,
    input  wire [NY-1:0] dark,
    input  wire          done,
    output reg  [NY-1:0] A_prev,
    output reg           restart
);
    localparam NP = W * H;
    localparam CW = (NP <= 1) ? 1 : $clog2(NP);

    reg [NY-1:0] A_max;
    reg [CW-1:0] oc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_prev  <= 0;
            A_max   <= 0;
            oc      <= 0;
            restart <= 1'b0;
        end else begin
            restart <= 1'b0;
            if (v) begin
                if (oc == NP-1) begin
                    A_prev <= (dark > A_max) ? dark : A_max;
                    A_max  <= 0;
                    oc     <= 0;
                end else begin
                    if (dark > A_max)
                        A_max <= dark;
                    oc <= oc + 1'b1;
                end
            end
            if (done)
                restart <= 1'b1;
        end
    end
endmodule
