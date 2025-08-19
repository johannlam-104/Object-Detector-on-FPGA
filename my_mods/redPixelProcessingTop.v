`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Johann Lam
// 
// Create Date: 07/21/2025 11:27:38 PM
// Design Name: 
// Module Name: RedPixelProcessingTop
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ProcessingTop#(
    parameter PROCESSING_LATENCY = 4 // clock cycles for the processing
)(
    input  wire         i_clk,
    input  wire         i_rstn,
    input  wire         i_flush,

    // Async FIFO input from camera
    input  wire [11:0]  i_data,
    input  wire         i_almostempty,
    output reg          o_rd_async_fifo, // controls async FIFO read

    // Final output FIFO interface
    input  wire         i_obuf_rd,
    output wire [11:0]  o_obuf_data,
    output wire [5:0]   o_obuf_fill,        
    output wire         o_obuf_full,
    output wire         o_obuf_almostfull,
    output wire         o_obuf_empty,
    output wire         o_obuf_almostempty
);

    // FSM
    reg din_valid, nxt_din_valid;
    reg nxt_rd, rd;
    reg state, nxt_state;

    localparam STATE_IDLE   = 1'b0,
               STATE_ACTIVE = 1'b1;

    // Kernel request for new data
    wire req;

    // Delay FIFO signals (raw pixel delay)
    wire        delay_wr, delay_rd, delay_empty;
    wire [11:0] delay_pixel;

    // Preprocessing buffer
    wire        preprocessed_red_pixel;
    wire        pp_write, pp_read, pp_empty;

    // Kernel controller window output
    wire [2:0]  r0_data, r1_data, r2_data;
    wire        kernel_valid;

    // Filtered red pixel output
    wire filtered_red_pixel;
    wire filtered_valid;

    // Centroid outputs
    wire [9:0] centroid_x;
    wire [8:0] centroid_y;
    wire       red_object_valid, end_frame;

    // Overlay IO
    wire [11:0] overlay_pixel;
    wire        overlay_valid_internal;

    // Back-pressure: only advance the raw-pixel path when the out FIFO can take data
    wire can_output = !o_obuf_full && !o_obuf_almostfull;

    // FSM Logic
    always @(*) begin
        nxt_state     = state;
        nxt_rd        = 1'b0;
        nxt_din_valid = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (!i_almostempty && req && !o_obuf_almostfull) begin
                    nxt_rd        = 1'b1;
                    nxt_din_valid = 1'b1;
                    nxt_state     = STATE_ACTIVE;
                end
            end

            STATE_ACTIVE: begin
                if (!i_almostempty && req && !o_obuf_almostfull) begin
                    nxt_rd        = 1'b1;
                    nxt_din_valid = 1'b1;
                end else begin
                    nxt_state = STATE_IDLE;
                end
            end
        endcase
    end

    always @(posedge i_clk) begin
        if (!i_rstn || i_flush) begin
            state           <= STATE_IDLE;
            rd              <= 1'b0;
            din_valid       <= 1'b0;
            o_rd_async_fifo <= 1'b0;
        end else begin
            state           <= nxt_state;
            rd              <= nxt_rd;
            din_valid       <= nxt_din_valid;
            o_rd_async_fifo <= nxt_rd;
        end
    end

    // 1-cycle register for raw pixel alongside the valid
    reg [11:0] i_data_d;
    reg        din_valid_d;
    always @(posedge i_clk) begin
        if (!i_rstn || i_flush) begin
            i_data_d    <= 12'd0;
            din_valid_d <= 1'b0;
        end else begin
            i_data_d    <= i_data;
            din_valid_d <= din_valid;
        end
    end

    // Preprocess & buffering
    wire pp_valid;
    wire red_pixel_flag;
    assign pp_write = pp_valid;          // write preprocessed flag this cycle
    assign delay_wr = din_valid_d;        // write raw pixel next cycle (to align with preprocess latency)
    assign pp_read  = req && !pp_empty;   // kernel pulls as needed
    

    // Red Pixel Thresholding (1-cycle)
    pp_redPixelDetector threshold_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn && (~i_flush)),
        
        .i_valid        (din_valid),
        .i_pixel        (i_data),
        
        .o_pixel_is_red (red_pixel_flag),
        .o_valid        (pp_valid)
    );

    // sync fifo right after preprocessing (stores 1-bit flags)
    fifo_sync #(
        .DATA_WIDTH(1),
        .ADDR_WIDTH(5)
    ) preprocessing_fifo_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn && (~i_flush)),

        .i_wr    (pp_write),
        .i_data  (red_pixel_flag),

        .i_rd    (pp_read),
        .o_data  (preprocessed_red_pixel),

        .o_fill  (), 
        .o_full(), 
        .o_almostfull(), 
        .o_empty(pp_empty), 
        .o_almostempty(), 
        .o_error()
    );


    // Kernel Controller (3x3 window)
    ps_kernel_control #(
        .LINE_LENGTH(640),
        .LINE_COUNT (480),
        .DATA_WIDTH (1),
        .CLAMP_EDGES(1)
    ) kernel_ctrl_i (
        .i_clk     (i_clk),
        .i_rstn    (i_rstn && (~i_flush)),

        .i_data    (preprocessed_red_pixel),
        .i_valid   (pp_read),
        .o_req     (req),

        .o_r0_data (r0_data),
        .o_r1_data (r1_data),
        .o_r2_data (r2_data),
        .o_valid   (kernel_valid)
    );

    // 3x3 Red Pixel Filter (2-cycle)
    ps_redPixelFilter redPixelFilter_i (
        .i_clk     (i_clk),
        .i_rstn    (i_rstn && (~i_flush)),

        .i_r0_data (r0_data),
        .i_r1_data (r1_data),
        .i_r2_data (r2_data),
        .i_valid   (kernel_valid),

        .o_red_pixel_valid (filtered_red_pixel),
        .o_valid           (filtered_valid)
    );

    // Centroid (lags by 1 full frame but fine)
    centroidCalc #(
        .IMG_WIDTH      (640),
        .IMG_HEIGHT     (480),
        .PIXEL_THRESHOLD(1000)
    ) centroid_calc_i (
        .i_clk             (i_clk),
        .i_rstn            (i_rstn && (~i_flush)),

        .i_valid_red_pixel (filtered_red_pixel),
        .i_valid           (filtered_valid),

        .o_centroid_x      (centroid_x),
        .o_centroid_y      (centroid_y),
        .o_valid           (/* unused */),
        .o_red_object_valid(red_object_valid),
        .o_end_frame       (end_frame)
    );

    // Delay pipeline bring-up counter
    reg [5:0] delay_fill_counter;
    reg       delay_ready;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn || i_flush) begin
            delay_fill_counter <= 0;
            delay_ready        <= 0;
        end else if (delay_wr && !delay_ready) begin
            delay_fill_counter <= delay_fill_counter + 1'b1;
            if (delay_fill_counter == PROCESSING_LATENCY - 1) begin
                delay_ready <= 1'b1;
            end
        end
    end

    // Raw Pixel Delay FIFO
    // Read only when the output path can accept data (back-pressure)
    assign delay_rd = delay_ready && !delay_empty && can_output;

    fifo_sync #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(5)
    ) delay_fifo_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn && (~i_flush)),

        .i_wr    (delay_wr),
        .i_data  (i_data_d),

        .i_rd    (delay_rd),
        .o_data  (delay_pixel),

        .o_fill  (), 
        .o_full(), 
        .o_almostfull(), 
        .o_empty(delay_empty), 
        .o_almostempty(), 
        .o_error()
    );
    
    // debugging signals to test crosshairoverlay
    wire        dbg_force_red  = 1'b1;      // force ON
    wire [9:0]  dbg_cx         = 10'd320;   // mid-screen
    wire [8:0]  dbg_cy         = 9'd240;

    // Overlay (consume only when we pop from delay FIFO)
    crossHairOverlay #(
        .CROSSHAIR_SIZE(7),
        .IMG_WIDTH     (640),
        .IMG_HEIGHT    (480)
    ) overlay_i (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn && (~i_flush)),

        .i_data_valid (delay_rd),     // drive valid directly from the gated delay read
        .i_data       (delay_pixel),

        .i_centroid_x (centroid_x), // original signal: centroid_x // force signal: dbg_cx
        .i_centroid_y (centroid_y), // original signal: centroid_y // force signal: dbg_cy
        .i_end_frame  (end_frame), 
        .i_red_object_valid(red_object_valid), // original signal: red_object_valid // force signal: dbg_force_red

        .o_data_valid (overlay_valid_internal),
        .o_data       (overlay_pixel)
    );

    // Output FIFO (writes only when overlay produced a valid)
    fifo_sync #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(5)
    ) output_fifo_i (
        .i_clk         (i_clk),
        .i_rstn        (i_rstn && (~i_flush)),

        .i_wr          (overlay_valid_internal),
        .i_data        (overlay_pixel),

        .i_rd          (i_obuf_rd),
        .o_data        (o_obuf_data),

        .o_fill        (o_obuf_fill),

        .o_full        (o_obuf_full),
        .o_almostfull  (o_obuf_almostfull),
        .o_empty       (o_obuf_empty),
        .o_almostempty (o_obuf_almostempty),
        .o_error       (/* unused */)
    );

endmodule

