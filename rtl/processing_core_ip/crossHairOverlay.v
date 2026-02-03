
`timescale 1ns/1ps
module crossHairOverlay #(
    parameter CROSSHAIR_SIZE   = 10,
    parameter IMG_WIDTH        = 640,
    parameter IMG_HEIGHT       = 480,
    parameter PENDING_DURATION = 4
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // input from delay fifo (raw)
    input  wire        i_tvalid,
    input  wire [31:0] i_tdata,
    input  wire        i_tuser,
    input  wire        i_tlast,
    output wire        o_tready,

    // centroid sideband (from previous frame)
    input  wire [9:0]  i_centroid_x,
    input  wire [8:0]  i_centroid_y,
    input  wire        i_end_frame,        // publish pulse (early)
    input  wire        i_red_object_valid, // qualifies that frame

    // output to obuf fifo
    output reg         o_tvalid,
    output reg  [31:0] o_tdata,
    output reg         o_tuser,
    output reg         o_tlast,
    input  wire        i_tready
);
    
    // -----------------------------
    // State
    // -----------------------------
    localparam [1:0] S_RESET   = 2'd0;
    localparam [1:0] S_DRAW    = 2'd1;
    localparam [1:0] S_PENDING = 2'd2;

    reg [1:0] state, next_state;

    // pending counter counts PIXELS (beats), not clocks
    localparam PENDW = (PENDING_DURATION <= 1) ? 1 : $clog2(PENDING_DURATION + 1);
    reg [PENDW-1:0] pend_cnt, next_pend_cnt;

    // committed centroid used for CURRENT raw frame drawing
    reg        has_red;
    reg [9:0]  cen_x;
    reg [8:0]  cen_y;

    // next centroid captured from publish (for NEXT raw frame)
    reg        next_has_red;
    reg [9:0]  next_cen_x;
    reg [8:0]  next_cen_y;

    // raster counters (advance on fire)
    reg [9:0] x_counter;
    reg [8:0] y_counter;
    wire last_x = (x_counter == IMG_WIDTH-1);

    // crosshair predicate
    wire [9:0] dx = (x_counter > cen_x) ? (x_counter - cen_x) : (cen_x - x_counter);
    wire [8:0] dy = (y_counter > cen_y) ? (y_counter - cen_y) : (cen_y - y_counter);
    wire draw_crosshair = has_red && ((dx <= CROSSHAIR_SIZE) || (dy <= CROSSHAIR_SIZE));

    wire [31:0] overlay_pixel = draw_crosshair ? 32'h0000_F800 : i_tdata; // red
    
    // -----------------------------
    // AXI 1-deep output register
    // -----------------------------
    assign o_tready = i_tready || !o_tvalid;
    wire in_fire = i_tvalid && o_tready;   // accepted input beat
    wire out_fire = o_tvalid && i_tready;   // accepted output beat
    
    // -----------------------------
    // Next-state logic (FSM)
    // -----------------------------
    always @* begin
      next_state    = state;
      next_pend_cnt = pend_cnt;
    
      case (state)
        S_RESET: begin
          // wait until the first SOF beat is actually accepted
          if (in_fire && i_tuser) next_state = S_DRAW;
        end
    
        S_DRAW: begin
          // enter pending when centroid publishes (sideband)
          // (pending itself counts beats via in_fire)
          if (i_end_frame) begin
            next_state    = S_PENDING;
            next_pend_cnt = PENDING_DURATION[PENDW-1:0];
          end
        end
    
        S_PENDING: begin
          // count down in *pixels accepted* (beats), not clocks
          if (in_fire) begin
            if (pend_cnt != 0)
              next_pend_cnt = pend_cnt - {{(PENDW-1){1'b0}},1'b1};
          end
    
          if (pend_cnt == 0)
            next_state = S_DRAW;
        end
    
        default: next_state = S_RESET;
      endcase
    end
    
    // -----------------------------
    // Sequential
    // -----------------------------
    always @(posedge i_clk) begin
      if (!i_rstn) begin
        state     <= S_RESET;
        pend_cnt  <= 0;
    
        has_red   <= 1'b0;
        cen_x     <= 10'd0;
        cen_y     <= 9'd0;
    
        next_has_red <= 1'b0;
        next_cen_x   <= 10'd0;
        next_cen_y   <= 9'd0;
    
        x_counter <= 10'd0;
        y_counter <= 9'd0;
    
        o_tvalid <= 1'b0;
        o_tdata  <= 32'h0;
        o_tuser  <= 1'b0;
        o_tlast  <= 1'b0;
      end else begin
        state    <= next_state;
        pend_cnt <= next_pend_cnt;
    
        // capture centroid decision on publish (sideband, independent of stall)
        if (i_end_frame) begin
          next_has_red <= i_red_object_valid;
          next_cen_x   <= i_centroid_x;
          next_cen_y   <= i_centroid_y;
        end
    
        // commit centroid at SOF of the RAW stream *when that SOF beat is accepted*
        if (in_fire && i_tuser) begin
          has_red <= next_has_red;
          cen_x   <= next_cen_x;
          cen_y   <= next_cen_y;
    
          x_counter <= 10'd0;
          y_counter <= 9'd0;
        end
        else if (in_fire) begin
          // advance raster only when we accepted an input beat
          if (last_x) begin
            x_counter <= 10'd0;
            if (y_counter != IMG_HEIGHT-1) y_counter <= y_counter + 1'b1;
            else                           y_counter <= 9'd0;
          end else begin
            x_counter <= x_counter + 1'b1;
          end
        end
    
        // -----------------------------
        // Output reg-slice behavior
        // -----------------------------
        if (in_fire) begin
          // we are accepting a new beat -> overwrite output regs with new transformed beat
          o_tvalid <= 1'b1;
    
          // compute overlay on the CURRENT counters (before they advance)
          // (overlay_pixel is combinational from x_counter/y_counter/cen_x/cen_y/i_tdata)
          o_tdata  <= overlay_pixel;
          o_tuser  <= i_tuser;
          o_tlast  <= i_tlast;
        end
        else if (out_fire) begin
          // sink consumed, no new beat accepted => output becomes empty
          o_tvalid <= 1'b0;
        end
        // else: hold output stable while stalled or idle
      end
    end
endmodule
