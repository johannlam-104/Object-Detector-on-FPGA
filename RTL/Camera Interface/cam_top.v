// cam_top.v
//
// Encapsulates all camera-related modules into a single block.
//
// cam_top.v
module cam_top 
  #(parameter T_CFG_CLK = 10,      // ns per cfg clk @100 MHz
    parameter FIFO_PTR_WIDTH = 9   
  )(
    input  wire        i_cfg_clk, // 100MHz 
    input  wire        i_rstn,

    // OV7670 I/O
    input  wire        i_cam_pclk, // 25MHz
    input  wire        i_cam_vsync,
    input  wire        i_cam_href,
    input  wire [7:0]  i_cam_data,

    // bidirectional I2C pins to sensor
    inout  wire        CAM_SCL,
    inout  wire        CAM_SDA,

    // Output Buffer FIFO (read side in 100 MHz domain)
    input  wire        i_obuf_rclk,
    input  wire        i_obuf_rstn,
    input  wire        i_obuf_rd,
    output wire [15:0] o_obuf_data,
    output wire        o_obuf_empty,
    output wire        o_obuf_almostempty,
    output wire [FIFO_PTR_WIDTH-1:0] o_obuf_fill,

    // Configuration Control
    input  wire        i_cfg_init,
    output wire        o_cfg_done,

    // Status
    output wire        o_sof
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

  // =========================
  // Capture -> FIFO signals
  // =========================
  wire        obuf_wr;
  wire [15:0] obuf_wdata;

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
  capture capture_i (
    .i_pclk     (i_cam_pclk),
    .i_rstn     (i_rstn),
    .i_cfg_done (o_cfg_done),
    .o_status   (),                
    .i_vsync    (i_cam_vsync),
    .i_href     (i_cam_href),
    .i_data     (i_cam_data),
    .o_wr       (obuf_wr),
    .o_wdata    (obuf_wdata),
    .o_sof      (o_sof)
  );

  // -------------------------
  // Async FIFO (24 MHz -> 100 MHz)
  // -------------------------
  fifo_async #(
    .DATA_WIDTH         (16),
    .PTR_WIDTH          (FIFO_PTR_WIDTH),
    .ALMOSTFULL_OFFSET  (2),
    .ALMOSTEMPTY_OFFSET (2)
  ) frontFIFO_i (
    // write side @ i_cam_pclk
    .i_wclk         (i_cam_pclk),
    .i_wrstn        (i_rstn),
    .i_wr           (obuf_wr),
    .i_wdata        (obuf_wdata),
    .o_wfull        (),
    .o_walmostfull  (),
    .o_wfill        (),

    // read side @ i_obuf_rclk (100 MHz)
    .i_rclk         (i_obuf_rclk),
    .i_rrstn        (i_obuf_rstn),
    .i_rd           (i_obuf_rd),
    .o_rdata        (o_obuf_data),
    .o_rempty       (o_obuf_empty),
    .o_ralmostempty (o_obuf_almostempty),
    .o_rfill        (o_obuf_fill)
  );

endmodule


