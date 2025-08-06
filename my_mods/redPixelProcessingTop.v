`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
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
    parameter PROCESSING_LATENCY = 12 // clock cycles for the processing
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
    output wire [4:0]   o_obuf_fill,
    output wire         o_obuf_full,
    output wire         o_obuf_almostfull,
    output wire         o_obuf_empty,
    output wire         o_obuf_almostempty
);

    // FSM
    reg din_valid, nxt_din_valid;
    reg nxt_rd, rd;
    reg state, nxt_state;

    localparam STATE_IDLE = 1'b0,
               STATE_ACTIVE = 1'b1;

    // Kernel request for new data
    wire req;
    
    
    // Delay FIFO signals
    wire delay_wr, delay_rd, delay_empty;
    wire [11:0] delay_pixel;

    // Red pixel threshold output
    wire red_pixel_flag;
    wire red_pixel_valid;

    // Kernel controller window output
    wire [2:0] r0_data, r1_data, r2_data;
    wire       kernel_valid;

    // Filtered red pixel output
    wire filtered_red_pixel;
    wire filtered_valid;

    // Centroid outputs
    wire [9:0] centroid_x, centroid_y;
    wire       red_object_valid, end_frame;

    // Overlay outputs
    wire [11:0] overlay_pixel;
    wire        overlay_valid;
    wire        overlay_valid_internal;
    wire        overlay_ready;
    
    // preprocessing buffer
    wire preprocessed_red_pixel;
    wire pp_write, pp_read, pp_empty;

    // FSM Logic
    always @(*) begin
        nxt_state     = state;
        nxt_rd        = 1'b0;
        nxt_din_valid = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (!i_almostempty && req && !o_obuf_almostfull) begin
                    nxt_rd        = 1;
                    nxt_din_valid = 1;
                    nxt_state     = STATE_ACTIVE;
                end
            end
            STATE_ACTIVE: begin
                if (!i_almostempty && req && !o_obuf_almostfull) begin
                    nxt_rd        = 1;
                    nxt_din_valid = 1;
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
    
    reg [11:0] i_data_d;
    reg        din_valid_d;
    
    // delay din_valid from FSM by 1 cycle to account for preprocessing
    always @(posedge i_clk) begin
        if (!i_rstn || i_flush) begin
            i_data_d    <= 12'd0;
            din_valid_d <= 1'b0;
        end else begin
            i_data_d    <= i_data;
            din_valid_d <= din_valid;
        end
    end
    
    assign pp_write  = din_valid; // write into preprocessing buffer
    assign delay_wr  = din_valid_d; // delay the write into the delay buffer to account 1-cycle latency for pp
    

    
        
    assign pp_read = req && !pp_empty; // read from preprocessing buffer when kernel control needs data 


    
    
    // Red Pixel Thresholding
    pp_redPixelDetector threshold_i (
        .i_clk    (i_clk),
        .i_rstn   (i_rstn && ~i_flush),
        
        .i_valid  (din_valid),
        .i_pixel  (i_data),
        
        .o_pixel_is_red (red_pixel_flag),
        .o_valid  (red_pixel_valid)
    );
    
    //sync fifo right after preprocessing
    fifo_sync #(
        .DATA_WIDTH(1),
        .ADDR_WIDTH(5)
    ) preprocessing_fifo_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn && ~i_flush),
        
        .i_wr    (pp_write),
        .i_data  (red_pixel_flag),
        
        .i_rd    (pp_read),
        .o_data  (preprocessed_red_pixel),
        
        .o_empty (pp_empty)
    );

    // Kernel Controller
    ps_kernel_control #(
        .LINE_LENGTH(640),
        .LINE_COUNT(480),
        .DATA_WIDTH(1)
    ) kernel_ctrl_i (
        .i_clk     (i_clk),
        .i_rstn    (i_rstn && ~i_flush),
        
        .i_data    (preprocessed_red_pixel),
        .i_valid   (din_valid),
        .o_req     (req),
        
        .o_r0_data (r0_data),
        .o_r1_data (r1_data),
        .o_r2_data (r2_data),
        .o_valid   (kernel_valid)
    );

    // Red Pixel Filter (3x3 convolution)
    ps_redPixelFilter redPixelFilter_i (
        .i_clk     (i_clk),
        .i_rstn    (i_rstn && ~i_flush),
        
        .i_r0_data (r0_data),
        .i_r1_data (r1_data),
        .i_r2_data (r2_data),
        .i_valid   (kernel_valid),
        
        .o_red_pixel_valid(filtered_red_pixel),
        .o_valid   (filtered_valid)
    );

    // Centroid Calculator
    centroidCalc #(
        .IMG_WIDTH(640),
        .IMG_HEIGHT(480),
        .PIXEL_THRESHOLD(1000)
    ) centroid_calc_i (
        .i_clk             (i_clk),
        .i_rstn            (i_rstn && ~i_flush),
        
        .i_valid_red_pixel (filtered_red_pixel),
        .i_valid           (filtered_valid),
        
        .o_centroid_x        (centroid_x),
        .o_centroid_y        (centroid_y),
        .o_valid             (),
        .o_red_object_valid  (red_object_valid),
        .o_end_frame         (end_frame)
        
    );

    // Raw Pixel Delay FIFO
    fifo_sync #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(5)
    ) delay_fifo_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn && ~i_flush),
        
        .i_wr    (delay_wr),
        .i_data  (i_data_d),
        
        .i_rd    (delay_rd),
        .o_data  (delay_pixel),
        
        .o_empty (delay_empty)
    );
    
    // counter logic to delay reads from delay fifo
    assign overlay_ready = delay_rd;
    
    reg [5:0] delay_fill_counter;
    reg       delay_ready;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn || i_flush) begin
            delay_fill_counter <= 0;
            delay_ready        <= 0;
        end else if (delay_wr && !delay_ready) begin
            delay_fill_counter <= delay_fill_counter + 1;
            if (delay_fill_counter == PROCESSING_LATENCY - 1)
                delay_ready <= 1;
        end
    end
    
    assign delay_rd = delay_ready && !delay_empty;

    // Overlay
    crossHairOverlay #(
        .crosshair_thickness(8)
    ) overlay_i (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn && ~i_flush),
        
        .i_data_valid (overlay_ready),
        .i_data       (delay_pixel),
        
        .i_centroid_x (centroid_x),
        .i_centroid_y (centroid_y),
        .i_end_frame  (end_frame),
        .i_red_object_valid(red_object_valid),
        
        .o_data_valid (overlay_valid_internal),
        .o_data       (overlay_pixel)
    );

    // Output FIFO
    fifo_sync #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(5)
    ) output_fifo_i (
        .i_clk         (i_clk),
        .i_rstn        (i_rstn && ~i_flush),
        
        .i_wr          (overlay_valid_internal),
        .i_data        (overlay_pixel),
        
        .i_rd          (i_obuf_rd),
        .o_data        (o_obuf_data),
        
        .o_fill        (o_obuf_fill),
        
        .o_full        (o_obuf_full),
        .o_almostfull  (o_obuf_almostfull),
        .o_empty       (o_obuf_empty),
        .o_almostempty (o_obuf_almostempty)
    );
    
    

endmodule

