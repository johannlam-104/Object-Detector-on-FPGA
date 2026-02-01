
`timescale 1ns/1ps
module kernel_control_axis #(
    parameter LINE_LENGTH = 640,
    parameter LINE_COUNT  = 480,
    parameter DATA_WIDTH  = 3, // {red_px, tuser, tlast}
    parameter CLAMP_EDGES = 1
)(
    input  wire                      i_clk,
    input  wire                      i_rstn,

    // Input stream (AXIS-minimum)
    input  wire [DATA_WIDTH-1:0]     i_tdata,
    input  wire                      i_tvalid,
    output reg                       o_tready,

    // 3× window outputs (3 taps per row)
    output reg  [(3*DATA_WIDTH-1):0] o_r0_data,
    output reg  [(3*DATA_WIDTH-1):0] o_r1_data,
    output reg  [(3*DATA_WIDTH-1):0] o_r2_data,
    output reg                       o_tvalid,
    input  wire                      i_tready
);

    // ------------------------------------------------------------
    // FSM: priming until we have 3 full lines
    // ------------------------------------------------------------
    localparam RSTATE_PRIMING = 1'b0;
    localparam RSTATE_ACTIVE  = 1'b1;

    reg RSTATE, NEXT_RSTATE;

    wire priming = (RSTATE == RSTATE_PRIMING);
    wire active  = (RSTATE == RSTATE_ACTIVE);

    // ------------------------------------------------------------
    // Output skid buffer (1 beat): holds a window until accepted
    // ------------------------------------------------------------
    reg out_valid;
    reg [(3*DATA_WIDTH-1):0] out_r0, out_r1, out_r2;

    wire out_xfer = out_valid && i_tready;
    wire can_load = (!out_valid) || i_tready; // room to load/replace this cycle

    // Drive outputs from skid regs
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_tvalid <= 1'b0;
            o_r0_data <= 0;
            o_r1_data <= 0;
            o_r2_data <= 0;
        end else begin
            o_tvalid <= out_valid;
            o_r0_data <= out_r0;
            o_r1_data <= out_r1;
            o_r2_data <= out_r2;
        end
    end

    // ------------------------------------------------------------
    // Write-side trackers
    // ------------------------------------------------------------
    reg [$clog2(LINE_LENGTH)-1:0] w_x;
    reg [$clog2(LINE_COUNT)-1:0]  w_y_next;
    reg [1:0]                     w_sel;
    reg [1:0]                     lines_filled; // saturates at 3

    // ------------------------------------------------------------
    // Read-side trackers
    // ------------------------------------------------------------
    reg [$clog2(LINE_LENGTH)-1:0] r_x;
    reg [$clog2(LINE_COUNT)-1:0]  r_y;
    reg [1:0]                     r_sel;

    // Delay coords 1 cycle to match rd_fire_d1 (linebuffer output timing)
    reg [$clog2(LINE_LENGTH)-1:0] r_x_d1;
    reg [$clog2(LINE_COUNT)-1:0]  r_y_d1;
    reg [1:0]                     r_sel_d1;

    // ------------------------------------------------------------
    // Line buffer controls + outputs
    // ------------------------------------------------------------
    reg  [3:0] lineBuffer_wr;
    reg  [3:0] lineBuffer_rd;

    wire [(3*DATA_WIDTH-1):0] lB0_rdata, lB1_rdata, lB2_rdata, lB3_rdata;

    // ------------------------------------------------------------
    // Upstream ready: once primed, only accept input when we can also
    // advance the window producer without overflowing output (skid).
    // ------------------------------------------------------------
    wire primed_enough = (lines_filled >= 2'd3);
    wire input_ready   = (!primed_enough) ? 1'b1 : can_load; // stall input if output skid is full

    wire fire = i_tvalid && input_ready; // accepted input beat

    always @(posedge i_clk) begin
        if (!i_rstn) o_tready <= 1'b0;
        else         o_tready <= input_ready;
    end

    // ------------------------------------------------------------
    // PRIMING -> ACTIVE transition
    // ------------------------------------------------------------
    always @* begin
        NEXT_RSTATE = RSTATE;
        case (RSTATE)
            RSTATE_PRIMING: if (primed_enough) NEXT_RSTATE = RSTATE_ACTIVE;
            RSTATE_ACTIVE : NEXT_RSTATE = RSTATE_ACTIVE;
        endcase
    end

    always @(posedge i_clk) begin
        if (!i_rstn) RSTATE <= RSTATE_PRIMING;
        else         RSTATE <= NEXT_RSTATE;
    end

    // ------------------------------------------------------------
    // Write trackers advance only on accepted input beat
    // ------------------------------------------------------------
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            w_x          <= 0;
            w_sel        <= 2'd0;
            w_y_next     <= 0;
            lines_filled <= 2'd0;
        end else if (fire) begin
            if (w_x == LINE_LENGTH-1) begin
                w_x <= 0;
                w_sel <= (w_sel == 2'd3) ? 2'd0 : (w_sel + 2'd1);
                w_y_next <= (w_y_next == LINE_COUNT-1) ? 0 : (w_y_next + 1'b1);
                if (lines_filled != 2'd3)
                    lines_filled <= lines_filled + 2'd1;
            end else begin
                w_x <= w_x + 1'b1;
            end
        end
    end

    always @* begin
        lineBuffer_wr = 4'b0000;
        lineBuffer_wr[w_sel] = fire;
    end

    // ------------------------------------------------------------
    // Read step: only when ACTIVE, we accepted an input beat, and
    // we have room to capture the produced window (skid has space).
    // ------------------------------------------------------------
    wire rd_fire = active && fire && can_load;

    // rd_fire_d1 indicates "a new window is available now"
    reg rd_fire_d1;
    always @(posedge i_clk) begin
        if (!i_rstn) rd_fire_d1 <= 1'b0;
        else         rd_fire_d1 <= rd_fire;
    end

    // Seed read mapping when becoming active
    function [1:0] plus2_mod4(input [1:0] v);
        plus2_mod4 = v + 2'd2;
    endfunction

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            r_x   <= 0;
            r_y   <= 0;
            r_sel <= 2'd0;
            r_x_d1 <= 0;
            r_y_d1 <= 0;
            r_sel_d1 <= 2'd0;
        end else begin
            if (RSTATE == RSTATE_PRIMING && NEXT_RSTATE == RSTATE_ACTIVE) begin
                r_x   <= 0;
                r_y   <= (w_y_next < 2) ? (w_y_next + LINE_COUNT - 2) : (w_y_next - 2);
                r_sel <= plus2_mod4(w_sel);
            end else if (rd_fire) begin
                // capture current coords for the window that will become valid next cycle
                r_x_d1   <= r_x;
                r_y_d1   <= r_y;
                r_sel_d1 <= r_sel;

                if (r_x == LINE_LENGTH-1) begin
                    r_x <= 0;
                    r_y <= (r_y == LINE_COUNT-1) ? 0 : (r_y + 1'b1);
                    r_sel <= (r_sel == 2'd3) ? 2'd0 : (r_sel + 2'd1);
                end else begin
                    r_x <= r_x + 1'b1;
                end
            end
        end
    end

    // Read enables: assert only on rd_fire
    always @* begin
        lineBuffer_rd = 4'b0000;
        if (rd_fire) begin
            lineBuffer_rd = 4'b1111;
            case (r_sel)
                2'd0: lineBuffer_rd[2] = 1'b0;
                2'd1: lineBuffer_rd[3] = 1'b0;
                2'd2: lineBuffer_rd[0] = 1'b0;
                2'd3: lineBuffer_rd[1] = 1'b0;
            endcase
        end
    end

    // ------------------------------------------------------------
    // Combinational row select using delayed selectors (aligned to rd_fire_d1)
    // These are the windows that are stable during the cycle rd_fire_d1=1.
    // ------------------------------------------------------------
    reg [(3*DATA_WIDTH-1):0] sel_r0, sel_r1, sel_r2;

    always @* begin
        sel_r0 = 0; sel_r1 = 0; sel_r2 = 0;

        if (r_y_d1 == 0) begin
            case (r_sel_d1)
                2'd0: begin sel_r0 = lB0_rdata; sel_r1 = lB0_rdata; sel_r2 = lB1_rdata; end
                2'd1: begin sel_r0 = lB1_rdata; sel_r1 = lB1_rdata; sel_r2 = lB2_rdata; end
                2'd2: begin sel_r0 = lB2_rdata; sel_r1 = lB2_rdata; sel_r2 = lB3_rdata; end
                2'd3: begin sel_r0 = lB3_rdata; sel_r1 = lB3_rdata; sel_r2 = lB0_rdata; end
            endcase
        end else if (r_y_d1 == LINE_COUNT-1) begin
            case (r_sel_d1)
                2'd0: begin sel_r0 = lB3_rdata; sel_r1 = lB0_rdata; sel_r2 = lB0_rdata; end
                2'd1: begin sel_r0 = lB0_rdata; sel_r1 = lB1_rdata; sel_r2 = lB1_rdata; end
                2'd2: begin sel_r0 = lB1_rdata; sel_r1 = lB2_rdata; sel_r2 = lB2_rdata; end
                2'd3: begin sel_r0 = lB2_rdata; sel_r1 = lB3_rdata; sel_r2 = lB3_rdata; end
            endcase
        end else begin
            case (r_sel_d1)
                2'd0: begin sel_r0 = lB3_rdata; sel_r1 = lB0_rdata; sel_r2 = lB1_rdata; end
                2'd1: begin sel_r0 = lB0_rdata; sel_r1 = lB1_rdata; sel_r2 = lB2_rdata; end
                2'd2: begin sel_r0 = lB1_rdata; sel_r1 = lB2_rdata; sel_r2 = lB3_rdata; end
                2'd3: begin sel_r0 = lB2_rdata; sel_r1 = lB3_rdata; sel_r2 = lB0_rdata; end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Load/hold skid buffer
    // rd_fire_d1 means "window available now"
    // ------------------------------------------------------------
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            out_valid <= 1'b0;
            out_r0    <= 0;
            out_r1    <= 0;
            out_r2    <= 0;
        end else begin
            // consume if downstream accepted and no replacement this cycle
            if (out_xfer && !(rd_fire_d1 && can_load)) begin
                out_valid <= 1'b0;
            end

            // load/replace when a window is available and we have room
            if (rd_fire_d1 && can_load) begin
                out_r0    <= sel_r0;
                out_r1    <= sel_r1;
                out_r2    <= sel_r2;
                out_valid <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Line buffer instances
    // ------------------------------------------------------------
    ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH), .DATA_WIDTH(DATA_WIDTH), .CLAMP_EDGES(CLAMP_EDGES))
    LINEBUF0_i (.i_clk(i_clk), .i_rstn(i_rstn), .i_wr(lineBuffer_wr[0]), .i_wdata(i_tdata),
                .i_rd(lineBuffer_rd[0]), .o_rdata(lB0_rdata));

    ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH), .DATA_WIDTH(DATA_WIDTH), .CLAMP_EDGES(CLAMP_EDGES))
    LINEBUF1_i (.i_clk(i_clk), .i_rstn(i_rstn), .i_wr(lineBuffer_wr[1]), .i_wdata(i_tdata),
                .i_rd(lineBuffer_rd[1]), .o_rdata(lB1_rdata));

    ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH), .DATA_WIDTH(DATA_WIDTH), .CLAMP_EDGES(CLAMP_EDGES))
    LINEBUF2_i (.i_clk(i_clk), .i_rstn(i_rstn), .i_wr(lineBuffer_wr[2]), .i_wdata(i_tdata),
                .i_rd(lineBuffer_rd[2]), .o_rdata(lB2_rdata));

    ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH), .DATA_WIDTH(DATA_WIDTH), .CLAMP_EDGES(CLAMP_EDGES))
    LINEBUF3_i (.i_clk(i_clk), .i_rstn(i_rstn), .i_wr(lineBuffer_wr[3]), .i_wdata(i_tdata),
                .i_rd(lineBuffer_rd[3]), .o_rdata(lB3_rdata));

endmodule


