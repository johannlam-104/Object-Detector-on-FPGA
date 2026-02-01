
// cam_top_axis.v
//
// Encapsulates all camera-related modules into a single block.
//
// cam_top_axis.v
//
// MODIFICATIONS: implemented axi-stream output on the read side of the async fifo

module cam_top_axis 
  #(parameter T_CFG_CLK = 10,      // ns per cfg clk @100 MHz
    parameter FIFO_PTR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter ALMOSTFULL_OFFSET =  2,
    parameter ALMOSTEMPTY_OFFSET = 2   
  )(
    input  wire        i_cfg_clk, // 100MHz 
    input  wire        i_rstn,

    // OV7670 I/O
    input  wire        i_cam_pclk, // 24MHz
    input  wire        i_cam_vsync,
    input  wire        i_cam_href,
    input  wire [7:0]  i_cam_data,
    
    output wire        o_cam_rstn,
    output wire        o_cam_pwdn,

    // bidirectional I2C pins to sensor
    inout  wire        CAM_SCL,
    inout  wire        CAM_SDA,

    // Output Buffer FIFO (read side in 100 MHz domain)
    input  wire                         i_obuf_rclk, 
    input  wire                         i_obuf_rstn,
    
    // output buffer flags (used by processing core)
    output wire                         o_obuf_empty,
    output wire                         o_obuf_almostempty,
    output wire [FIFO_PTR_WIDTH-1:0]    o_obuf_fill,
    
    // axi-stream (S2MM) -> VDMA
    input  wire                         M_AXIS_TREADY,
    output wire                         M_AXIS_TVALID,
    output wire   [DATA_WIDTH-1:0]      M_AXIS_TDATA, 
    output wire                         M_AXIS_TUSER,   
    output wire                         M_AXIS_TLAST,   
    
    // Configuration Control
    input  wire        i_cfg_init,
    output wire        o_cfg_done,

    // Status
    output wire        o_ready // fifo isnt empty
  );

  // =========================
  // I2C inout <-> internal
  // =========================
  wire scl_in, sda_in;
  wire scl_oe, sda_oe;  // 1 = release (Hi-Z), 0 = drive low

  assign CAM_SCL = scl_oe ? 1'bz : 1'b0;
  assign CAM_SDA = sda_oe ? 1'bz : 1'b0;
  assign scl_in  = CAM_SCL;
  assign sda_in  = CAM_SDA;

    // Camera pins static
    assign o_cam_rstn = 1'b1; 
    assign o_cam_pwdn = 1'b0;


  // =========================
  // Capture -> FIFO signals
  // =========================
  wire        obuf_wr;
  wire [DATA_WIDTH+1:0] obuf_wdata; // 16 bit pixel + 2 bit metadata

  // -------------------------
  // Camera Configuration (SCCB)
  // -------------------------
  cfg_interface #(.T_CLK(T_CFG_CLK)) cfg_i (
    .i_clk   (i_cfg_clk),
    .i_rstn  (i_rstn),
    .i_start (i_cfg_init),
    .o_done  (o_cfg_done),

    .i_scl   (scl_in),
    .i_sda   (sda_in),
    .o_scl   (scl_oe),
    .o_sda   (sda_oe)
  );

  // -------------------------
  // Pixel Capture (24 MHz PCLK domain)
  // -------------------------
  cam_capture_axis capture_i (
    .i_pclk         (i_cam_pclk),
    .i_rstn         (i_rstn),
    .i_cfg_done     (o_cfg_done),
    .o_status       (),    
                
    . i_vsync       (i_cam_vsync),
    . i_href        (i_cam_href),
    . i_data        (i_cam_data),
    
    .o_mvalid       (obuf_wr),
    .o_tdata        (obuf_wdata),
    .i_sready       (o_ready),
    
    .o_overflow     ()
  );

  // -------------------------
  // Async FIFO (24 MHz -> 100 MHz)
  // -------------------------
  fifo_async_axis #(
    .TDATA_WIDTH         (DATA_WIDTH),
    .PTR_WIDTH          (FIFO_PTR_WIDTH),
    .ALMOSTFULL_OFFSET  (ALMOSTFULL_OFFSET),
    .ALMOSTEMPTY_OFFSET (ALMOSTEMPTY_OFFSET)
  ) frontFIFO_i (
    // write side @ i_cam_pclk
    .i_wclk          (i_cam_pclk),
    .i_wrstn         (i_rstn),
    
    // write side interface (compact axi-stream)
    .o_sready        (o_ready), // fifo not empty
    .i_wr_valid      (obuf_wr),
    .i_wr_data       (obuf_wdata),
    
    // read side
    .i_rclk          (i_obuf_rclk),
    .i_rrstn         (i_obuf_rstn),
    
    
    // AXI-STREAM -> VDMA
    .i_mready        (M_AXIS_TREADY),
    .o_rd_valid      (M_AXIS_TVALID),
    .o_rd_data       (M_AXIS_TDATA),
    .o_tuser         (M_AXIS_TUSER),
    .o_tlast         (M_AXIS_TLAST),
    
    // FIFO flags
    .o_wfull         (o_obuf_almostempty),
    .o_walmostfull   (o_obuf_fill),
     .o_wfill        (),
     
     .o_rempty       (o_obuf_empty),
     .o_ralmostempty (),
     .o_rfill        ()

  );

endmodule
`default_nettype wire
