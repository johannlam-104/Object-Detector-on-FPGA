module HDMI_top 
    (
    input  wire        i_p_clk,
    input  wire        i_tmds_clk,
    input  wire        i_resetn,
  
    input  wire [11:0]  i_pixel,
    
    input  wire        i_vsync,
    input  wire        i_hsync,
    input  wire        i_active_area,
 
    output wire [3:0]  o_TMDS_P,
    output wire [3:0]  o_TMDS_N
    );


    wire [9:0] channel_zero;
    wire [9:0] channel_one;
    wire [9:0] channel_two;
    
    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;
    
    // 1-cycle delay to align with converter latency
    reg vsync_d;
    reg hsync_d;
    reg active_d;
    always @(posedge i_p_clk) begin
        if (!i_resetn) begin
            vsync_d  <= 1'b0;
            hsync_d  <= 1'b0;
            active_d <= 1'b0;
        end 
        else begin
            vsync_d  <= i_vsync;
            hsync_d  <= i_hsync;
            active_d <= i_active_area;
        end
    end
    
    wire convertor_valid;
    
    RGB444_to_RGB888 convertor_i (
    .i_p_clk        (i_p_clk        ),
    .i_rstn         (~i_resetn      ),

    .i_data         (i_pixel        ),   // {R[11:8], G[7:4], B[3:0]}
    .i_valid        (i_active_area  ),

    .o_r_data       (red            ),
    .o_g_data       (green          ),
    .o_b_data       (blue           ),
    .o_valid        (convertor_valid)
    );
    
    HDMI_encode encode_i (
    .i_p_clk        (i_p_clk       ),
    .i_resetn       (i_resetn      ),
         
    .i_red          (red          ),
    .i_green        (green        ),
    .i_blue         (blue         ),
         
    .i_vsync        (vsync_d       ),
    .i_hsync        (hsync_d       ),
    .i_active_area  (active_d & convertor_valid),

    .o_tmds_red     (channel_zero  ),
    .o_tmds_green   (channel_one   ),
    .o_tmds_blue    (channel_two   )
    );

    HDMI_out out_i (
    .i_p_clk        (i_p_clk       ),
    .i_tmds_clk     (i_tmds_clk    ),
    .i_resetn       (i_resetn      ),

    .i_tmds_red     (channel_zero  ),
    .i_tmds_green   (channel_one   ),
    .i_tmds_blue    (channel_two   ),

    .o_TMDS_P       (o_TMDS_P      ),
    .o_TMDS_N       (o_TMDS_N      )
    );


endmodule
