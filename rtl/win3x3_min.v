`timescale 1ns/1ps
// Non-blocking streaming 3x3 window: 2 row-delay FIFOs + 2-deep column shift regs.
// The rightmost center (W-1) is computed at x=W-1 and emitted at x=0 of the next
// row, so the input accepts one pixel every cycle (no per-row stall).
// Host streams H+1 rows (last row = copy of row H-1); a 1-cycle tail emits the
// last rightmost center after the frame.
module win3x3_min #(
    parameter W    = 8,
    parameter H    = 8,
    parameter DW   = 8,
    parameter AUXW = 24
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire          in_valid,
    input  wire [DW-1:0]   in_data,
    input  wire [AUXW-1:0] in_aux,
    output wire          in_ready,
    output reg           out_valid,
    output reg  [DW-1:0]   out_blur,
    output reg  [DW-1:0]   out_center,
    output reg  [AUXW-1:0] out_aux,
    output reg           done
);
    localparam CW = DW + AUXW;
    localparam ST_IDLE = 3'd0, ST_CLEAR = 3'd1, ST_RUN = 3'd2,
               ST_TAIL = 3'd3, ST_DONE = 3'd4;

    localparam XW = (W <= 1) ? 1 : $clog2(W);
    localparam YW = (H + 1 <= 2) ? 1 : $clog2(H + 1);
    reg [2:0]  state;
    reg [XW-1:0] x;
    reg [YW-1:0] y;
    reg        clr;

    wire [CW-1:0] pack = { in_data, in_aux };
    wire [CW-1:0] p1, p2;
    wire e1, e2, full1, full2;

    wire wr1 = (state == ST_RUN) && in_valid;
    wire rd1 = (state == ST_RUN) && in_valid && (y >= 1);
    wire wr2 = (state == ST_RUN) && in_valid && (y >= 1);
    wire rd2 = (state == ST_RUN) && in_valid && (y >= 2);

    // depth W+1: row delay W, one extra slot so simultaneous write+read never hits full/empty
    // For large W (e.g. 10000) this must map to BRAM/external memory, not W-deep registers;
    // use fifo_line_bb.v for area estimation (blackbox, not counted as regs/LUTs).
    fifo_line #(.DEPTH(W+1), .DW(CW)) f1 (
        .clk(clk), .rst_n(rst_n), .clear(clr),
        .wr_en(wr1), .rd_en(rd1), .din(pack), .dout(p1), .empty(e1), .full(full1)
    );
    fifo_line #(.DEPTH(W+1), .DW(CW)) f2 (
        .clk(clk), .rst_n(rst_n), .clear(clr),
        .wr_en(wr2), .rd_en(rd2), .din(p1), .dout(p2), .empty(e2), .full(full2)
    );

    reg [CW-1:0] sr0_0, sr0_1;
    reg [CW-1:0] sr1_0, sr1_1;
    reg [CW-1:0] sr2_0, sr2_1;

    reg [DW-1:0] aL, aC, aR, cL, cC, cR, bL, bC, bR;
    integer min9;
    reg [DW-1:0] bRq;

    reg [DW-1:0]   e_blur, e_center;
    reg [AUXW-1:0] e_aux;

    assign in_ready = (state == ST_RUN);

    // helper: 3x3 weighted sum, rows (aL..aR, cL..cR, bL..bR)
    task automatic win_sum;
        begin
            min9 = aL;
            if (aC < min9) min9 = aC;
            if (aR < min9) min9 = aR;
            if (cL < min9) min9 = cL;
            if (cC < min9) min9 = cC;
            if (cR < min9) min9 = cR;
            if (bL < min9) min9 = bL;
            if (bC < min9) min9 = bC;
            if (bR < min9) min9 = bR;
            bRq = min9[DW-1:0];
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE; x <= 0; y <= 0; clr <= 0;
            done <= 0; out_valid <= 0; out_blur <= 0; out_center <= 0; out_aux <= 0;
            sr0_0 <= 0; sr0_1 <= 0; sr1_0 <= 0; sr1_1 <= 0; sr2_0 <= 0; sr2_1 <= 0;
            e_blur <= 0; e_center <= 0; e_aux <= 0;
        end else begin
            out_valid <= 1'b0;
            clr <= 1'b0;

            if (start) begin
                x <= 0; y <= 0; clr <= 1'b1;
                sr0_0 <= 0; sr0_1 <= 0;
                sr1_0 <= 0; sr1_1 <= 0;
                sr2_0 <= 0; sr2_1 <= 0;
                e_blur <= 0; e_center <= 0; e_aux <= 0;
                done <= 0;
                state <= ST_CLEAR;
            end else begin
            case (state)
            ST_IDLE: begin
                done <= 0;
            end

            ST_CLEAR: begin
                state <= ST_RUN;
            end

            ST_RUN: begin
                if (in_valid) begin
                    if (x == 0 && y >= 2) begin
                        out_blur   <= e_blur;
                        out_center <= e_center;
                        out_aux    <= e_aux;
                        out_valid  <= 1'b1;
                    end else if (x >= 1 && y >= 1) begin
                        bR = pack[CW-1:CW-DW];
                        bC = sr0_0[CW-1:CW-DW];
                        bL = (x >= 2) ? sr0_1[CW-1:CW-DW] : sr0_0[CW-1:CW-DW];
                        cR = p1[CW-1:CW-DW];
                        cC = sr1_0[CW-1:CW-DW];
                        cL = (x >= 2) ? sr1_1[CW-1:CW-DW] : sr1_0[CW-1:CW-DW];
                        if (y == 1) begin
                            aR = cR; aC = cC; aL = cL;
                        end else begin
                            aR = p2[CW-1:CW-DW];
                            aC = sr2_0[CW-1:CW-DW];
                            aL = (x >= 2) ? sr2_1[CW-1:CW-DW] : sr2_0[CW-1:CW-DW];
                        end
                        win_sum;
                        out_blur   <= bRq;
                        out_center <= sr1_0[CW-1:CW-DW];
                        out_aux    <= sr1_0[AUXW-1:0];
                        out_valid  <= 1'b1;
                    end

                    // capture rightmost center (W-1) at x=W-1 for next-row x=0
                    if (x == W-1) begin
                        bL = sr0_0[CW-1:CW-DW]; bC = pack[CW-1:CW-DW]; bR = pack[CW-1:CW-DW];
                        cL = sr1_0[CW-1:CW-DW]; cC = p1[CW-1:CW-DW]; cR = p1[CW-1:CW-DW];
                        if (y == 1) begin
                            aL = cL; aC = cC; aR = cR;
                        end else begin
                            aL = sr2_0[CW-1:CW-DW]; aC = p2[CW-1:CW-DW]; aR = p2[CW-1:CW-DW];
                        end
                        win_sum;
                        e_blur   <= bRq;
                        e_center <= p1[CW-1:CW-DW];
                        e_aux    <= p1[AUXW-1:0];
                    end

                    sr0_1 <= sr0_0;
                    sr0_0 <= pack;
                    if (y >= 1) begin sr1_1 <= sr1_0; sr1_0 <= p1; end
                    if (y >= 2) begin sr2_1 <= sr2_0; sr2_0 <= p2; end

                    if (x == W-1) begin
                        x <= 0;
                        if (y == H) begin
                            state <= ST_TAIL;
                        end else begin
                            y <= y + 1'b1;
                        end
                    end else begin
                        x <= x + 1'b1;
                    end
                end
            end

            ST_TAIL: begin
                out_blur   <= e_blur;
                out_center <= e_center;
                out_aux    <= e_aux;
                out_valid  <= 1'b1;
                done <= 1'b1;
                state <= ST_DONE;
            end

            ST_DONE: begin
                done <= 1'b1;
            end

            default: state <= ST_IDLE;
            endcase
            end
        end
    end
endmodule
