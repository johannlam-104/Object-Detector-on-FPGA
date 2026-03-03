
`timescale 1ns / 1ps

module processingCoreTop(
    input wire            i_clk,
    input wire            i_rstn,
                        
    input  wire [31:0]    S_AXIS_TDATA,
    input  wire           S_AXIS_TUSER,
    input  wire           S_AXIS_TLAST,
    input  wire           S_AXIS_TVALID,
    output wire           S_AXIS_TREADY,
    
    output  wire [31:0]   M_AXIS_TDATA , 
    output  wire          M_AXIS_TUSER , 
    output  wire          M_AXIS_TLAST , 
    output  wire          M_AXIS_TVALID,
    input   wire          M_AXIS_TREADY,
    
    output wire  [11:0]  output_rgb   ,
    output wire  [9:0]   output_x_coor,
    output wire  [8:0]   output_y_coor
    
    );
    
    // threshold signals
    wire [31:0] threshold_data ;
    wire        threshold_user ;
    wire        threshold_last ;
    wire        threshold_valid;
    wire        pack_ready     ;
    
    // axis pack signals
    wire [33:0] packed_data ;
    wire        packed_valid;
    wire        kernel_ready;
    
    // kernel signals
    wire [101:0] kernel_r0_data, kernel_r1_data, kernel_r2_data;
    wire kernel_valid;
    wire filter_ready;
    
    // filter signals
    wire [31:0]     filter_data   ;
    wire            filter_user   ;
    wire            filter_last   ;
    wire            filter_valid  ;
    wire            centroid_ready;
    
    // centroid signals
    wire [31:0]     centroid_data   ;
    wire            centroid_user   ;
    wire            centroid_last   ;
    wire            centroid_valid  ;
    wire            overlay_ready  ;
    
    wire [9:0]     centroid_x;
    wire [8:0]     centroid_y;
    wire           end_frame;
    wire           red_object_valid;
    
    // overlay signals
    wire            overlay_valid;
    wire  [31:0]    overlay_data ;
    wire            overlay_user ;
    wire            overlay_last ;
    wire            fifo_ready   ;
    
    // debugging
    assign          output_rgb = M_AXIS_TDATA[31:20];
    assign          output_x_coor = M_AXIS_TDATA[18:9];
    assign          output_y_coor = M_AXIS_TDATA[8:0];
    
    
    
    thresholding thesholding_i (
        .i_clk (i_clk),
        .i_rstn(i_rstn),
        
        // write side
        .i_tvalid(S_AXIS_TVALID), // per pixel valid
        .i_tdata (S_AXIS_TDATA),
        .i_tuser (S_AXIS_TUSER),
        .i_tlast (S_AXIS_TLAST),
        .o_tready(S_AXIS_TREADY), 
        
        // read side
        .o_tdata (threshold_data ), // pixel is red or not o_tdata[19]
        .o_tuser (threshold_user ), // sof
        .o_tlast (threshold_last ), // eol
        .o_tvalid(threshold_valid),
        .i_tready(pack_ready     ) // preprocessing fifo not full
    );
    
       axis_pack # (
        .TDATA_WIDTH       (32),
        .TUSER_WIDTH       (1 )
    ) pack_i (
        .i_clk      (i_clk      ),
        .i_rstn     (i_rstn     ),
        
        // write side  
        .i_tvalid(threshold_valid   ),
        .o_tready(pack_ready        ), // can accept data (always high)            
        .i_tdata (threshold_data    ),
        .i_tuser (threshold_user    ), // start of frame
        .i_tlast (threshold_last    ), // end of line
        
        // read side   
        .o_tvalid (packed_valid     ),           
        .i_tready (kernel_ready     ), // can output (from consumer/kernel)
        .o_tpacked(packed_data      )
        
    );
    
   kernel_control_axis #(
        .LINE_LENGTH (640),
        .LINE_COUNT  (480),
        .DATA_WIDTH  (34 ), // {32 bit data bus, tuser, tlast}
        .CLAMP_EDGES (1  )
    ) kernel_i (
        .i_clk (i_clk),
        .i_rstn(i_rstn),
    
        // Input stream (AXIS-minimum)
        .i_tdata (packed_data),
        .i_tvalid(packed_valid),
        .o_tready(kernel_ready),
    
        // 3× window outputs (3 taps per row)
        .o_r0_data(kernel_r0_data),
        .o_r1_data(kernel_r1_data),
        .o_r2_data(kernel_r2_data),
        .o_tvalid (kernel_valid),
        .i_tready (filter_ready)
    );

    ps_redPixelFilter filter_i (
        .i_clk (i_clk ),
        .i_rstn(i_rstn),

        // 3x3 window rows, each row = {L[33:0], C[33:0], R[33:0]}
        .i_r0_data(kernel_r0_data), // 34 x 3
        .i_r1_data(kernel_r1_data),
        .i_r2_data(kernel_r2_data),

        // input stream valid/ready for the window update
        .i_tvalid(kernel_valid),
        .o_tready(filter_ready),

        // output AXIS (mask stream)
        .o_tdata (filter_data   ),   // original data bus (1-bit)
        .o_tuser (filter_user   ),   // SOF of center pixel
        .o_tlast (filter_last   ),   // EOL of center pixel
        .o_tvalid(filter_valid  ),
        .i_tready(centroid_ready)
    );
    
    
    centroidCalc #(
        .IMG_WIDTH      (640 ),
        .IMG_HEIGHT     (480 ),
        .PIXEL_THRESHOLD(1000),
        .EOF_EARLY_BEATS(5)
        ) centroid_i (
        .i_clk              (i_clk ),
        .i_rstn             (i_rstn),

        // write side
        .i_tdata            (filter_data ),
        .i_tuser            (filter_user ),
        .i_tlast            (filter_last ),
        .i_tvalid           (filter_valid),
        .o_tready           (centroid_ready),

        // read side (pass-through stream for alignment/debug)
        .o_tdata            (centroid_data ),
        .o_tvalid           (centroid_valid ),
        .o_tuser            (centroid_user ),
        .o_tlast            (centroid_last ),
        .i_tready           (overlay_ready ),

        // metadata to overlay (sticky to eof)
        .o_centroid_x       (centroid_x      ),
        .o_centroid_y       (centroid_y      ),
        .o_end_frame        (end_frame       ),
        .o_red_object_valid (red_object_valid)
    );
    
    crossHairOverlay #(
        .CROSSHAIR_SIZE   (10 ),
        .IMG_WIDTH        (640),
        .IMG_HEIGHT       (480),
        .PENDING_DURATION (5  )
        ) overlay_i (
        .i_clk (i_clk ),
        .i_rstn(i_rstn),

        // input from delay fifo (raw)
        .i_tvalid               (centroid_valid),
        .i_tdata                (centroid_data),
        .i_tuser                (centroid_user),
        .i_tlast                (centroid_last),
        .o_tready               (overlay_ready),

        // centroid input (from previous frame)
        .i_centroid_x           (centroid_x      ),
        .i_centroid_y           (centroid_y      ),
        .i_end_frame            (end_frame       ),        // publish pulse (early)
        .i_red_object_valid     (red_object_valid), // qualifies that frame

        // output to obuf fifo
        .o_tvalid               (overlay_valid),
        .o_tdata                (overlay_data ),
        .o_tuser                (overlay_user ),
        .o_tlast                (overlay_last ),
        .i_tready               (fifo_ready   )
    );
    
    fifo_sync #(
        .TDATA_WIDTH (32),
        .TUSER_WIDTH (1 ),
        .ADDR_WIDTH  (9 )
        ) obuf_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        // write side
        .i_tvalid       (overlay_valid),
        .o_tready       (fifo_ready),
        .i_tdata        (overlay_data),
        .i_tuser        (overlay_user),
        .i_tlast        (overlay_last),

        // read side
        .o_tvalid       (M_AXIS_TVALID ),
        .i_tready       (M_AXIS_TREADY ),
        .o_tdata        (M_AXIS_TDATA ),
        .o_tuser        (M_AXIS_TUSER),
        .o_tlast        (M_AXIS_TLAST)

    );
    
    
    
endmodule





