
`timescale 1ns/1ps
module kernel_control_axis #(
    parameter LINE_LENGTH = 640,
    parameter LINE_COUNT  = 480,
    parameter DATA_WIDTH  = 34,
    parameter CLAMP_EDGES = 1
)(
    input  wire                      i_clk,
    input  wire                      i_rstn,

    input  wire [DATA_WIDTH-1:0]     i_tdata,
    input  wire                      i_tvalid,
    output wire                      o_tready,

    output reg  [(3*DATA_WIDTH-1):0] o_r0_data,
    output reg  [(3*DATA_WIDTH-1):0] o_r1_data,
    output reg  [(3*DATA_WIDTH-1):0] o_r2_data,
    output reg                       o_tvalid,
    input  wire                      i_tready
);

// ----------------------------------------------------------------
// Widths
// ----------------------------------------------------------------
localparam X_BITS = $clog2(LINE_LENGTH);
localparam Y_BITS = $clog2(LINE_COUNT);

// ----------------------------------------------------------------
// lines_filled: needs 3 bits so it can actually hold value 3
// ----------------------------------------------------------------
reg [2:0] lines_filled;
wire      primed_enough = (lines_filled == 3'd3);

// ----------------------------------------------------------------
// FSM
// ----------------------------------------------------------------
localparam PRIMING = 1'b0, ACTIVE = 1'b1;
reg state;
wire going_active = (state == PRIMING) && primed_enough;

always @(posedge i_clk)
    if (!i_rstn) state <= PRIMING;
    else if (going_active) state <= ACTIVE;

// ----------------------------------------------------------------
// AXIS skid buffer - ONE level, direct registered output
// ----------------------------------------------------------------
wire out_space = (!o_tvalid) || i_tready;  // downstream will consume, or empty
wire out_xfer  = o_tvalid && i_tready;

assign o_tready = (!primed_enough) ? 1'b1 : out_space;

wire fire = i_tvalid && o_tready;

// ----------------------------------------------------------------
// Write trackers
// ----------------------------------------------------------------
reg [X_BITS-1:0] w_x;
reg [Y_BITS-1:0] w_y_next;
reg [1:0]        w_sel;

always @(posedge i_clk) begin
    if (!i_rstn) begin
        w_x          <= 0;
        w_sel        <= 2'd0;
        w_y_next     <= 0;
        lines_filled <= 3'd0;
    end else if (fire) begin
        if (w_x == LINE_LENGTH-1) begin
            w_x          <= 0;
            w_sel        <= w_sel + 2'd1;          // natural 2-bit wrap
            w_y_next     <= (w_y_next == LINE_COUNT-1) ? 0 : w_y_next + 1'b1;
            if (lines_filled < 3'd3)
                lines_filled <= lines_filled + 3'd1;
        end else begin
            w_x <= w_x + 1'b1;
        end
    end
end

// ----------------------------------------------------------------
// Line buffer write enables
// ----------------------------------------------------------------
reg [3:0] lineBuffer_wr;
always @* begin
    lineBuffer_wr = 4'b0;
    lineBuffer_wr[w_sel] = fire;
end

// ----------------------------------------------------------------
// Read trackers
// ----------------------------------------------------------------
reg [X_BITS-1:0] r_x;
reg [Y_BITS-1:0] r_y;
reg [1:0]        r_sel;

// rd_fire: produce a window read this cycle; result valid next cycle
wire rd_fire = (state == ACTIVE) && fire && out_space;

// Capture coords to align with the 1-cycle linebuffer read latency
reg [X_BITS-1:0] r_x_d1;
reg [Y_BITS-1:0] r_y_d1;
reg [1:0]        r_sel_d1;
reg              rd_fire_d1;

function automatic [1:0] plus2_mod4(input [1:0] v);
    plus2_mod4 = v + 2'd2;
endfunction

always @(posedge i_clk) begin
    if (!i_rstn) begin
        r_x       <= 0;
        r_y       <= 0;
        r_sel     <= 2'd0;
        r_x_d1    <= 0;
        r_y_d1    <= 0;
        r_sel_d1  <= 2'd0;
        rd_fire_d1 <= 1'b0;
    end else begin
        rd_fire_d1 <= rd_fire;   // pipeline the "window ready" flag

        if (going_active) begin
            // Align read pointer: start 2 lines behind current write line
            r_x   <= 0;
            r_y   <= (w_y_next < 2) ? (w_y_next + LINE_COUNT - 2) : (w_y_next - 2);
            r_sel <= plus2_mod4(w_sel);
        end else if (rd_fire) begin
            // Latch current coords for the delayed mux
            r_x_d1  <= r_x;
            r_y_d1  <= r_y;
            r_sel_d1 <= r_sel;

            // Advance read pointer
            if (r_x == LINE_LENGTH-1) begin
                r_x   <= 0;
                r_y   <= (r_y == LINE_COUNT-1) ? 0 : r_y + 1'b1;
                r_sel <= r_sel + 2'd1;
            end else begin
                r_x <= r_x + 1'b1;
            end
        end
    end
end

// ----------------------------------------------------------------
// Line buffer read enables
// ----------------------------------------------------------------
reg [3:0] lineBuffer_rd;
always @* begin
    lineBuffer_rd = 4'b0;
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

// ----------------------------------------------------------------
// Row mux (aligned to rd_fire_d1 via _d1 coords)
// ----------------------------------------------------------------
wire [(3*DATA_WIDTH-1):0] lB0_rdata, lB1_rdata, lB2_rdata, lB3_rdata;

reg [(3*DATA_WIDTH-1):0] sel_r0, sel_r1, sel_r2;
always @* begin
    sel_r0 = 0; sel_r1 = 0; sel_r2 = 0;
    if (r_y_d1 == 0) begin
        case (r_sel_d1)
            2'd0: begin sel_r0=lB0_rdata; sel_r1=lB0_rdata; sel_r2=lB1_rdata; end
            2'd1: begin sel_r0=lB1_rdata; sel_r1=lB1_rdata; sel_r2=lB2_rdata; end
            2'd2: begin sel_r0=lB2_rdata; sel_r1=lB2_rdata; sel_r2=lB3_rdata; end
            2'd3: begin sel_r0=lB3_rdata; sel_r1=lB3_rdata; sel_r2=lB0_rdata; end
        endcase
    end else if (r_y_d1 == LINE_COUNT-1) begin
        case (r_sel_d1)
            2'd0: begin sel_r0=lB3_rdata; sel_r1=lB0_rdata; sel_r2=lB0_rdata; end
            2'd1: begin sel_r0=lB0_rdata; sel_r1=lB1_rdata; sel_r2=lB1_rdata; end
            2'd2: begin sel_r0=lB1_rdata; sel_r1=lB2_rdata; sel_r2=lB2_rdata; end
            2'd3: begin sel_r0=lB2_rdata; sel_r1=lB3_rdata; sel_r2=lB3_rdata; end
        endcase
    end else begin
        case (r_sel_d1)
            2'd0: begin sel_r0=lB3_rdata; sel_r1=lB0_rdata; sel_r2=lB1_rdata; end
            2'd1: begin sel_r0=lB0_rdata; sel_r1=lB1_rdata; sel_r2=lB2_rdata; end
            2'd2: begin sel_r0=lB1_rdata; sel_r1=lB2_rdata; sel_r2=lB3_rdata; end
            2'd3: begin sel_r0=lB2_rdata; sel_r1=lB3_rdata; sel_r2=lB0_rdata; end
        endcase
    end
end

// ----------------------------------------------------------------
// Output register IS the skid buffer
// Load when: window is ready (rd_fire_d1) AND we have space
// Hold when: valid but not accepted
// Clear when: accepted and no incoming window
// ----------------------------------------------------------------
always @(posedge i_clk) begin
    if (!i_rstn) begin
        o_tvalid  <= 1'b0;
        o_r0_data <= 0;
        o_r1_data <= 0;
        o_r2_data <= 0;
    end 
    else begin
        if (rd_fire_d1) begin
            // New window arrived - load it (out_space was guaranteed at rd_fire time)
            o_r0_data <= sel_r0;
            o_r1_data <= sel_r1;
            o_r2_data <= sel_r2;
            o_tvalid  <= 1'b1;
        end 
        else if (out_xfer && !rd_fire_d1) begin
            // Downstream consumed, nothing new arriving
            o_tvalid  <= 1'b0;
        end
    end
end

// ----------------------------------------------------------------
// Line buffer instances
// ----------------------------------------------------------------
ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH),.DATA_WIDTH(DATA_WIDTH),.CLAMP_EDGES(CLAMP_EDGES))
LINEBUF0_i(.i_clk(i_clk),.i_rstn(i_rstn),.i_wr(lineBuffer_wr[0]),.i_wdata(i_tdata),
           .i_rd(lineBuffer_rd[0]),.o_rdata(lB0_rdata));

ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH),.DATA_WIDTH(DATA_WIDTH),.CLAMP_EDGES(CLAMP_EDGES))
LINEBUF1_i(.i_clk(i_clk),.i_rstn(i_rstn),.i_wr(lineBuffer_wr[1]),.i_wdata(i_tdata),
           .i_rd(lineBuffer_rd[1]),.o_rdata(lB1_rdata));

ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH),.DATA_WIDTH(DATA_WIDTH),.CLAMP_EDGES(CLAMP_EDGES))
LINEBUF2_i(.i_clk(i_clk),.i_rstn(i_rstn),.i_wr(lineBuffer_wr[2]),.i_wdata(i_tdata),
           .i_rd(lineBuffer_rd[2]),.o_rdata(lB2_rdata));

ps_linebuffer #(.LINE_LENGTH(LINE_LENGTH),.DATA_WIDTH(DATA_WIDTH),.CLAMP_EDGES(CLAMP_EDGES))
LINEBUF3_i(.i_clk(i_clk),.i_rstn(i_rstn),.i_wr(lineBuffer_wr[3]),.i_wdata(i_tdata),
           .i_rd(lineBuffer_rd[3]),.o_rdata(lB3_rdata));

endmodule
