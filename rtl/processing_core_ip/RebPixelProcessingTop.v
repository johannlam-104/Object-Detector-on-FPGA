`timescale 1ns / 1ps

module ProcessingTop#(
    // frame size (active area)
    parameter IMG_WIDTH = 640,
    parameter IMG_HEIGHT = 480,
    
    // pending and processing decoupling
    parameter PENDING_DURATION = 3,
    
    // crosshair semantics
    parameter PIXEL_THRESHOLD = 1000,
    parameter CROSSHAIR_SIZE = 10,
    
    // fifo specifications
    parameter RAW_DATA_WIDTH = 32, // raw pixel (keep at 32 for vdma)
    parameter PROCESSED_DATA_WIDTH = 1,
    parameter ADDR_WIDTH = 11,
    parameter ALMOSTFULL_OFFSET = 1,
    parameter ALMOSTEMPTY_OFFSET = 1,
    parameter FIFO_PTR_WIDTH = 9,
    
    // data widths from cam
    parameter TUSER_WIDTH = 1,
    parameter CAM_DATA_WIDTH = 32
    
)(
    input  wire         i_clk,
    input  wire         i_rstn,
    input  wire         i_flush, // default '0', no flush

    // Async FIFO axi-stream input from camera
    input  wire     [CAM_DATA_WIDTH-1:0]    i_tdata,
    input  wire                             i_tvalid,
    input  wire     [TUSER_WIDTH-1:0]       i_tuser,
    input  wire                             i_tlast,
    input  wire                             i_empty,   // empty flag from async fifo
    output reg                              o_tready, // controls async FIFO read (o_tready)

    // Final axi-stream output FIFO -> VDMA
    output wire                             o_tvalid,           
    input  wire                             i_tready, // can output (from vdma)
    output wire  [RAW_DATA_WIDTH-1:0]       o_tdata,
    output wire  [TUSER_WIDTH-1:0]          o_tuser,
    output wire                             o_tlast,
    
    output wire                             o_obuf_empty
        
);

    // FSM
    reg din_valid, nxt_din_valid;
    reg nxt_rd, rd;
    reg state, nxt_state;

    localparam STATE_IDLE   = 1'b0,
               STATE_ACTIVE = 1'b1;

    // Back-pressure: only gate the OUTPUT path; let processing run freely
    wire obuf_full;
    wire can_output = !obuf_full;
    wire pp_full, pp_empty;
    wire delay_buf_ready; // delay fifo not full
    
    // FSM driven async fifo read Logic
    always @(*) begin
        nxt_state     = state;
        nxt_rd        = 1'b0;
        nxt_din_valid = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (!i_empty && !obuf_full && !pp_full && delay_buf_ready && i_tvalid && i_tready) begin 
                    nxt_rd        = 1'b1;
                    nxt_din_valid = 1'b1;
                    nxt_state     = STATE_ACTIVE;
                end
            end

            STATE_ACTIVE: begin
                if (!i_empty && !obuf_full && !pp_full && delay_buf_ready && i_tvalid && i_tready) begin 
                    nxt_rd        = 1'b1;
                    nxt_din_valid = 1'b1;
                end 
                else begin
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
            o_tready        <= 1'b0;
        end 
        else begin
            state           <= nxt_state;
            rd              <= nxt_rd;
            din_valid       <= nxt_din_valid;
            o_tready        <= nxt_rd;
        end
    end
    
    wire red_pixel_flag;
    wire pp_ready;
    wire tuser_pp_in;
    wire tlast_pp_in;
    
    wire pp_valid_in, pp_valid_out;
    wire red_pixel_flag_bufr_out;
    wire tuser_pp_out, tlast_pp_out;
    
    wire obuf_ready;
    wire overlay_ready;

    // Red Pixel Thresholding (1-cycle)
    pp_redPixelDetector threshold_i (
        .i_clk      (i_clk),
        .i_rstn     (i_rstn),
        
        
        .i_tvalid   (din_valid), // per pixel valid
        .i_tdata    (i_tdata),
        .i_tuser    (i_tuser),
        .i_tlast    (i_tlast),
        .o_tready   (/*unused*/), // always high
        
        
        .o_tdata    (red_pixel_flag), // pixel is red or not
        .o_tuser    (tuser_pp_in), // sof
        .o_tlast    (tlast_pp_in), // eol
        .o_tvalid   (pp_valid_in),
        .i_tready   (pp_ready) // preprocessing fifo not full
    );
    
    // axi-s pack and buffering
    wire pack_ready;
    
    // fifo errors (dropped beats)
    wire pp_fifo_error, delay_fifo_error, obuf_error;
    
    // sync fifo right after preprocessing (stores 1-bit flags and passes metadata)
    fifo_sync #(
        .TDATA_WIDTH             (PROCESSED_DATA_WIDTH   ),
        .ADDR_WIDTH             (ADDR_WIDTH             ),
        .ALMOSTFULL_OFFSET      (ALMOSTFULL_OFFSET      ),
        .ALMOSTEMPTY_OFFSET     (ALMOSTEMPTY_OFFSET     )
    ) preprocessing_fifo_i (
        .i_clk          (i_clk                  ),
        .i_rstn         (i_rstn                ),

        .i_tvalid       (pp_valid_in            ),
        .o_tready       (pp_ready               ),
        .i_tdata        (red_pixel_flag         ),
        .i_tuser        (tuser_pp_in            ),
        .i_tlast        (tlast_pp_in            ),
         
        .o_tvalid       (pp_valid_out           ), 
        .i_tready       (pack_ready             ), 
        .o_tdata        (red_pixel_flag_bufr_out), 
        .o_tuser        (tuser_pp_out           ),
        .o_tlast        (tlast_pp_out           ),
        
        
     // .o_fill         (/*unused*/             ),       
       
        .o_full         (pp_full                ),       
     // .o_almostfull   (/*unused*/             ), 
        .o_empty        (pp_empty               )      
     // .o_almostempty  (/*unused*/             ),
       
     // .o_error        (pp_fifo_error          )
    );       
    
    // axi-stream packed signals
    wire packed_in;
    assign packed_in = red_pixel_flag_bufr_out;
    wire [2:0] packed_out;
    wire valid_packed_out;
    
    // kernel control signals
    wire kernel_ready;
    
    
    // axis_pack (packs all the metadata into the same bus)
    axis_pack #(
        .TDATA_WIDTH(1),
        .TUSER_WIDTH(1)
    ) pack_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        // write side  
        .i_tvalid       (pp_valid_out),
        .o_tready       (pack_ready), // can accept data (always high)            
        .i_tdata        (packed_in),
        .i_tuser        (tuser_pp_out), // start of frame
        .i_tlast        (tlast_pp_out), // end of line
        
        // read side   
        .o_tvalid       (valid_packed_out),           
        .i_tready       (kernel_ready), // can output (from consumer/kernel)
        .o_tpacked      (packed_out)
        
    );
    
    // pack <-> kernel <-> filter signals
    wire [2:0] kernel_data_in = packed_out;
    wire kernel_valid_in = valid_packed_out;
    
    wire kernel_valid_out;
    
    wire filter_ready;
    
    // Kernel controller window output
    wire [8:0]  r0_data, r1_data, r2_data;

    
    // Kernel Controller (3x3 window)
    kernel_control_axis #(
        .LINE_LENGTH (IMG_WIDTH),
        .LINE_COUNT  (IMG_HEIGHT),
        .DATA_WIDTH  (3  ), // 3-bits {red_px, tuser, tlast}
        .CLAMP_EDGES (1'b1)
    ) kernel_cntrl_i(
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
    
        // Input stream (AXIS-minimum)
        .i_tdata        (kernel_data_in),
        .i_tvalid       (kernel_valid_in),
        .o_tready       (kernel_ready),
    
        // 3× window outputs (3 taps per row)
        .o_r0_data      (r0_data),
        .o_r1_data      (r1_data),
        .o_r2_data      (r2_data),
        .o_tvalid       (kernel_valid_out),
        .i_tready       (filter_ready)
    );
    
    // Kernel <-> Filter <-> centroid signals
    wire filter_valid_in = kernel_valid_out;
    
    wire filter_data_out;
    wire filter_tuser_out;
    wire filter_tlast_out;
    wire filter_valid_out;
    
    wire centroid_ready; // ready from centroid module (always high)
    
    // 3x3 Red Pixel Filter (2-cycle)
    ps_redPixelFilter #(
        .TDATA_WIDTH(1),
        .TUSER_WIDTH(1)
    )redpixfilter_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
    
        // 3x3 window rows, each row = {L[2:0], C[2:0], R[2:0]}
        .i_r0_data      (r0_data),
        .i_r1_data      (r1_data),
        .i_r2_data      (r2_data),
    
        // input stream valid/ready for the window update
        .i_tvalid       (filter_valid_in),
        .o_tready       (filter_ready),
    
        // output AXIS (mask stream)
        .o_tdata        (filter_data_out ),   // filtered red (1-bit)
        .o_tuser        (filter_tuser_out),   // SOF of center pixel
        .o_tlast        (filter_tlast_out),   // EOL of center pixel
        .o_tvalid       (filter_valid_out),
        .i_tready       (centroid_ready)
    );
    
    wire delay_valid_in = o_tready && !i_empty; // async fifo pop
    wire [31:0] delay_data_in = i_tdata;
    wire delay_user_in = i_tuser;
    wire delay_last_in = i_tlast;
    wire delay_full;
    
    wire delay_valid_out;
    wire [31:0] delay_data_out;
    wire delay_user_out;
    wire delay_last_out;
    
    reg  delay_ready, next_delay_ready;
    
    fifo_sync #(
      .TDATA_WIDTH        (RAW_DATA_WIDTH),
      .TUSER_WIDTH        (TUSER_WIDTH ),
      .ADDR_WIDTH         (ADDR_WIDTH ),
      .ALMOSTFULL_OFFSET  (ALMOSTFULL_OFFSET ),
      .ALMOSTEMPTY_OFFSET (ALMOSTEMPTY_OFFSET )
      ) delay_fifo_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
    // write side (
        .i_tvalid       (delay_valid_in),
        .o_tready       (delay_buf_ready   ),       
        .i_tdata        (delay_data_in),
        .i_tuser        (delay_user_in),        
        .i_tlast        (delay_last_in),        
   
    // read side         
        .o_tvalid       (delay_valid_out),        
        .i_tready       (delay_ready    ), // from fsm driven alignment signal
        .o_tdata        (delay_data_out ),
        .o_tuser        (delay_user_out ),
        .o_tlast        (delay_last_out ),
    
    // flags
    //  .o_fill         (/*unused*/),
        
        .o_full         (delay_full),
    //  .o_almostfull   (/*unused*/),
        .o_empty        (/*unused*/)
    //  .o_almostempty  (/*unused*/),
        
    //  .o_error        (delay_fifo_error)
    );
    
    
    wire cen_data_in  = filter_data_out ;
    wire cen_user_in  = filter_tuser_out;
    wire cen_last_in  = filter_tlast_out;
    wire cen_valid_in = filter_valid_out;
    
    wire cen_user_out ;
    wire cen_last_out ;
    wire cen_valid_out;
    
    // Centroid outputs
    wire [9:0] centroid_x       ;
    wire [8:0] centroid_y       ;
    wire       red_object_valid ;
    wire       end_frame;

    // Centroid (lags by 1 full frame but fine)
    centroidCalc #(
        .IMG_WIDTH       (IMG_WIDTH ),
        .IMG_HEIGHT      (IMG_HEIGHT ),
        .PIXEL_THRESHOLD (PIXEL_THRESHOLD)
    ) centroid_calc_i (
        .i_clk                      (i_clk),
        .i_rstn                     (i_rstn),
        
        // write side
        .i_tdata                    (cen_data_in    ),    // filtered red flag (per pixel)
        .i_tuser                    (cen_user_in    ),
        .i_tlast                    (cen_last_in    ),
        .i_tvalid                   (cen_valid_in   ),    // per-pixel enable (same beat as x/y)
        .o_tready                   (centroid_ready ),    // always high
       
        // read side
        .o_tvalid                   (cen_valid_out  ),    
        .o_tuser                    (cen_user_out   ),    // when o_tuser && cen_valid_out is high (start pipeline)
        .o_tlast                    (cen_last_out   ),
        .i_tready                   (1'b1           ),    // original: overlay_ready
       
        // metadata to overlay
        .o_centroid_x               (centroid_x      ),
        .o_centroid_y               (centroid_y      ),
        .o_red_object_valid         (red_object_valid),  // level: result of last commit
        .o_end_frame                (end_frame       )   // 1-cycle pulse before actual eof
    );
    
    // FSM driven delay fifo read logic
    reg [1:0] RD_STATE, NEXT_RD_STATE;
    localparam RD_STATE_IDLE   = 2'b10,
               RD_STATE_ACTIVE = 2'b11;
    
    always @(*) begin
        NEXT_RD_STATE          = RD_STATE;
        next_delay_ready       = 1'b0;

        case (RD_STATE)
            RD_STATE_IDLE: begin
                // when first observed beat is passed thru centroid and output buffer not full
                if (cen_valid_out && overlay_ready) begin // original: also gated by cen_user_out
                    next_delay_ready        = 1'b1;
                    NEXT_RD_STATE           = RD_STATE_ACTIVE;
                end
            end

            RD_STATE_ACTIVE: begin
                // steady state, delay fifo can be continously read from until reset
                NEXT_RD_STATE = RD_STATE_ACTIVE;
                next_delay_ready = overlay_ready;
            end
        endcase
    end

    always @(posedge i_clk) begin
        if (!i_rstn || i_flush) begin
            RD_STATE        <= RD_STATE_IDLE;
            delay_ready     <= 1'b0;
        end 
        else begin
            RD_STATE        <= NEXT_RD_STATE;
            delay_ready     <= next_delay_ready;
        end
    end
    
    
    wire overlay_valid_in = delay_valid_out;
    
    wire [31:0] overlay_data_in = delay_data_out ;
    wire overlay_user_in = delay_user_out ;
    wire overlay_last_in = delay_last_out ;
    
    wire overlay_valid_out;
    wire [31:0] overlay_data_out;
    wire overlay_user_out;
    wire overlay_last_out;
    
    // Overlay (consume on the shared beat)
    crossHairOverlay #(
        .CROSSHAIR_SIZE   (CROSSHAIR_SIZE   ), // thickness = 2*CROSSHAIR_SIZE + 1
        .IMG_WIDTH        (IMG_WIDTH        ),
        .IMG_HEIGHT       (IMG_HEIGHT       ),
        .PENDING_DURATION (PENDING_DURATION )
    )overlay_i (
        .i_clk              (i_clk),
        .i_rstn             (i_rstn),
        
        // axi-stream input from delay fifo
        .i_tvalid           (overlay_valid_in),  // raw pixel data valid
        .i_tdata            (overlay_data_in),
        .i_tuser            (overlay_user_in), // switch frames on this signal
        .i_tlast            (overlay_last_in),
        .o_tready           (overlay_ready), // tells delay fifo if ready to receive
        
        // centroid signals
        .i_centroid_x       (centroid_x      ),
        .i_centroid_y       (centroid_y      ),
        .i_end_frame        (end_frame),        // AFTER publish from centroidCalc (commit/commit_d)
        .i_red_object_valid (red_object_valid), // sticky across frame in centroid domain
        
        // output to output buffer
        .o_tvalid           (overlay_valid_out),
        .o_tdata            (overlay_data_out),
        .o_tuser            (overlay_user_out),
        .o_tlast            (overlay_last_out), // pulse at last pixel of each line
        .i_tready           (obuf_ready) // output buffer not full
            
    );
    
    wire obuf_valid_in = overlay_valid_out;
    wire [31:0] obuf_data_in = overlay_data_out;
    wire obuf_user_in = overlay_user_out;
    wire obuf_last_in = overlay_last_out;
    
    // Output FIFO (writes only when overlay produced a valid).
    // Back-pressure only here; the processing chain continues, the delay FIFO
    // absorbs the natural latency so frames stay aligned.
    fifo_sync
        #(.TDATA_WIDTH        (32),
          .TUSER_WIDTH        (1 ),
          .ADDR_WIDTH         (9 ),
          .ALMOSTFULL_OFFSET  (2 ),
          .ALMOSTEMPTY_OFFSET (2 )
          ) obuf_i (
        .i_clk              (i_clk),
        .i_rstn             (i_rstn),
        
        // write side  
        .i_tvalid           (obuf_valid_in),
        .o_tready           (obuf_ready),        // fifo not full/can accept data             
        .i_tdata            (obuf_data_in),
        .i_tuser            (obuf_user_in),        // start of frame
        .i_tlast            (obuf_last_in),        // end of line
        
        // read side   
        .o_tvalid           (o_tvalid ),                  
        .i_tready           (i_tready ),        // can output, from VDMA
        .o_tdata            (o_tdata  ),
        .o_tuser            (o_tuser  ),
        .o_tlast            (o_tlast  ),
        
        // flags
     // .o_fill             (),
        
        .o_full             (obuf_full),
     // .o_almostfull       (),
        .o_empty            (o_obuf_empty)
     // .o_almostempty      (),
        
     // .o_error            (obuf_error)
    );

endmodule
