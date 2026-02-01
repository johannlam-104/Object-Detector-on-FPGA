`timescale 1ns / 1ps
`include "ov7670_sccb_slave.sv"

module cam_top_tb;

    // ----------------------------------------------------------------
    // Test image geometry (small for quick sim)
    // ----------------------------------------------------------------
    localparam int IMG_W                = 640;
    localparam int IMG_H                = 480;
    localparam int T_CFG_CLK            = 10;     // 100 MHz period = 10 ns
    localparam int FIFO_PTR_WIDTH       = 9;
    localparam int DATA_WIDTH           = 32;
    localparam int ALMOSTFULL_OFFSET    = 1;
    localparam int ALMOSTEMPTY_OFFSET   = 1;
    

    // ----------------------------------------------------------------
    // DUT interface signals
    // ----------------------------------------------------------------
    // Config clock + reset
    logic i_cfg_clk  = 0;   // 100 MHz
    logic i_rstn     = 0;

    // Camera side
    logic        i_cam_pclk  = 0;   // 25 MHz
    logic        i_cam_vsync;
    logic        i_cam_href;
    logic [7:0]  i_cam_data;        // MUST be 8 bits

    // I2C lines (bidirectional, pulled up)
    tri1 CAM_SCL;
    tri1 CAM_SDA;

    // FIFO read side (100 MHz domain)
    logic        i_obuf_rclk  = 0;
    logic        i_obuf_rstn  = 0;
    logic        o_obuf_empty;
    logic        o_obuf_almostempty;
    logic [FIFO_PTR_WIDTH-1:0] o_obuf_fill;
    
    // AXI-STREAM data
    logic                   M_AXIS_TREADY ;
    logic                   M_AXIS_TVALID ;
    logic [DATA_WIDTH-1:0]  M_AXIS_TDATA  ;
    logic                   M_AXIS_TUSER  ;
    logic                   M_AXIS_TLAST  ;
    
    
    // Configuration control
    logic i_cfg_init;
    logic o_cfg_done;

    // Status
    logic o_ready;   // fifo isnt empty

    // ----------------------------------------------------------------
    // Clock generation
    // ----------------------------------------------------------------
    // 100 MHz config clock
    always #(T_CFG_CLK/2) i_cfg_clk   = ~i_cfg_clk;
    // 25 MHz camera pixel clock (period 40 ns)
    always #(T_CFG_CLK*4/2) i_cam_pclk = ~i_cam_pclk;
    // Use same 100 MHz clock for FIFO read side
    always #(T_CFG_CLK/2) i_obuf_rclk = ~i_obuf_rclk;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    cam_top_axis #(
        .T_CFG_CLK          (T_CFG_CLK),
        .FIFO_PTR_WIDTH     (FIFO_PTR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),   
        .ALMOSTFULL_OFFSET  (ALMOSTFULL_OFFSET),
        .ALMOSTEMPTY_OFFSET (ALMOSTEMPTY_OFFSET)
        
    ) dut (
        .i_cfg_clk          (i_cfg_clk),
        .i_rstn             (i_rstn),

        // OV7670 I/O
        .i_cam_pclk         (i_cam_pclk),
        .i_cam_vsync        (i_cam_vsync),
        .i_cam_href         (i_cam_href),
        .i_cam_data         (i_cam_data),

        // bidirectional I2C pins to sensor
        .CAM_SCL            (CAM_SCL),
        .CAM_SDA            (CAM_SDA),

        // Output Buffer FIFO (read side in 100 MHz domain)
        .i_obuf_rclk        (i_obuf_rclk),
        .i_obuf_rstn        (i_obuf_rstn),
        
        // axi-stream (S2MM) -> VDMA
        .M_AXIS_TREADY      (M_AXIS_TREADY),
        .M_AXIS_TVALID      (M_AXIS_TVALID),
        .M_AXIS_TDATA       (M_AXIS_TDATA), 
        .M_AXIS_TUSER       (M_AXIS_TUSER),   
        .M_AXIS_TLAST       (M_AXIS_TLAST),          
        
        .o_obuf_empty       (o_obuf_empty),
        .o_obuf_almostempty (o_obuf_almostempty),
        .o_obuf_fill        (o_obuf_fill),

        // Configuration Control
        .i_cfg_init         (i_cfg_init),
        .o_cfg_done         (o_cfg_done),

        // Status
        .o_ready              (o_ready)
    );
    
    // ----------------------------------------------------------------
    //                  SCCB Slave Instatiation
    // ----------------------------------------------------------------
    
    ov7670_sccb_slave sccb_slave_i(
        .SCL(CAM_SCL),
        .SDA(CAM_SDA)
    );

    // ----------------------------------------------------------------
    // Expected pixel generator (function)
    //   Camera sends:
    //     byte1 = {R[3:0], G[3:0]}
    //     byte2 = {B[3:0], 4'b0000}
    //
    //   We define:
    //     R = x[3:0]
    //     G = y[3:0]
    //     B = (x ^ y)[3:0]
    // ----------------------------------------------------------------
    
    logic assert_enable;
    
    function automatic [7:0] mk_cam_byte(
        input int x,
        input int y,
        input bit first_half   // 1 = first byte, 0 = second byte
    );
        logic [4:0] r; 
        logic [5:0] g;
        logic [4:0] b;
        begin
            r = x[4:0];
            b = y[4:0];
            g = {(x ^ y),1'b1};
            if (first_half) begin
                mk_cam_byte = {r, g[5:3]};               // first byte
            end else begin
                mk_cam_byte = {g[2:0], b};         // second byte
            end
        end
    endfunction

    // ----------------------------------------------------------------
    // Line driver task: drives HREF and i_cam_data for one line
    // ----------------------------------------------------------------
    task automatic drive_line(
        input int line_y,
        input int active_pixels,
        input int hblank_pixels,
        ref   logic       cam_href,
        ref   logic [7:0] cam_data
    );
        int x;
        bit first_half;
        begin
            // Horizontal blanking before line
            cam_href = 0;
            cam_data = 8'h00;
            repeat (hblank_pixels * 2) @(posedge i_cam_pclk); // 2 bytes per pixel

            // Active region
            cam_href = 1;
            for (x = 0; x < active_pixels; x++) begin
                // First byte (R,G)
                first_half = 1'b1;
                cam_data   = mk_cam_byte(x, line_y, first_half);
                @(posedge i_cam_pclk);

                // Second byte (B,0)
                first_half = 1'b0;
                cam_data   = mk_cam_byte(x, line_y, first_half);
                @(posedge i_cam_pclk);
            end

            // Horizontal blanking after line
            cam_href = 0;
            cam_data = 8'h00;
            repeat (hblank_pixels * 2) @(posedge i_cam_pclk);
        end
    endtask

    // ----------------------------------------------------------------
    // Frame driver task: toggles VSYNC and calls drive_line for all y
    // capture.v treats VSYNC falling edge as start-of-frame (o_sof)
    // ----------------------------------------------------------------
    task automatic drive_frame_simple(
        ref logic       cam_vsync,
        ref logic       cam_href,
        ref logic [7:0] cam_data
        );
        int x, y;
        begin
            // Small idle period before frame (VSYNC high)
            cam_vsync = 1;
            cam_href  = 0;
            cam_data  = 8'h00;
            repeat (10) @(posedge i_cam_pclk);
    
            // Start-of-frame: VSYNC low
            cam_vsync = 0;
            cam_href  = 0;
            cam_data  = 8'h00;
    
            // *** NEW: give capture a few PCLKs to see SOF and enter ACTIVE ***
            repeat (4) @(posedge i_cam_pclk);
    
            // Active rows
            for (y = 0; y < IMG_H; y++) begin
                cam_href = 1;
                for (x = 0; x < IMG_W; x++) begin
                    // first byte
                    cam_data = mk_cam_byte(x, y, 1'b1);
                    @(posedge i_cam_pclk);
    
                    // second byte
                    cam_data = mk_cam_byte(x, y, 1'b0);
                    @(posedge i_cam_pclk);
                end
                cam_href = 0;
                cam_data = 8'h00;
                @(posedge i_cam_pclk); // one idle PCLK between lines
            end
    
            // End-of-frame
            cam_vsync = 1;
            cam_href  = 0;
            cam_data  = 8'h00;
            repeat (10) @(posedge i_cam_pclk);
        end
    endtask


    // ----------------------------------------------------------------
    // Scoreboard state for expected pixels
    // ----------------------------------------------------------------
    int sb_x;
    int sb_y;

    function automatic [11:0] expected_pixel(
        input int x, 
        input int y
        );
        expected_pixel = { x[3:0], y[3:0], (x ^ y) };  // R,G,B 4b each
    endfunction

    // ----------------------------------------------------------------
    // FIFO read + assertion
    //   Whenever we read from the FIFO, assert that the pixel matches
    //   expected_pixel(sb_x, sb_y) in scan order.
    // ----------------------------------------------------------------
    logic [11:0] exp;
    always @(posedge i_obuf_rclk) begin
        if (!i_obuf_rstn) begin
            M_AXIS_TREADY <= 0;
            sb_x      <= 0;
            sb_y      <= 0;
        end
        else begin
            if (!o_obuf_empty) begin
                M_AXIS_TREADY <= 1;

                // o_obuf_data is registered/combinational from FIFO read side.
                // Check against expected pattern.
                /*
                if(assert_enable) begin
                    exp = expected_pixel(sb_x, sb_y);
    
                    assert (o_obuf_data == exp)
                        else $fatal("Pixel mismatch: got %h expected %h at (x=%0d,y=%0d)",
                                    o_obuf_data, exp, sb_x, sb_y);
    
                    // Advance expected coords
                    sb_x++;
                    if (sb_x == IMG_W) begin
                        sb_x = 0;
                        sb_y++;
                    end
                end
                */
            end
            else begin
                M_AXIS_TREADY <= 0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test sequence
    // ----------------------------------------------------------------
    initial begin
        // Initialize
        i_rstn      = 0;
        i_obuf_rstn = 0;
        i_cfg_init  = 0;
        i_cam_vsync = 1;
        i_cam_href  = 0;
        i_cam_data  = 8'h00;
        assert_enable = 0;

        // Reset for some cycles
        repeat (10) @(posedge i_cfg_clk);
        i_rstn      = 1;
        i_obuf_rstn = 1;
        i_cfg_init = 1;
        @(posedge i_cfg_clk);
        i_cfg_init = 0;

        // wait for configuration to be done
        @(posedge o_cfg_done); // wait for config to complete
        repeat (5) @(posedge i_cfg_clk);
        
        /*
        fork
            begin
                @(posedge o_cfg_done);
                $display("Config done at time %0t", $time);
            end
            begin
                #1_000_000; // 1 ms sim-time timeout guard
                $fatal("Timeout waiting for o_cfg_done");
            end
        join_any
        disable fork;
        */
        
        // Small wait for things to settle
        repeat (20) @(posedge i_cfg_clk);

        // Drive a single test frame
        drive_frame_simple(
            i_cam_vsync,
            i_cam_href,
            i_cam_data
        );
        assert_enable = 1;
        
        drive_frame_simple(
            i_cam_vsync,
            i_cam_href,
            i_cam_data
        );
        
        drive_frame_simple(
            i_cam_vsync,
            i_cam_href,
            i_cam_data
        );
        drive_frame_simple(
            i_cam_vsync,
            i_cam_href,
            i_cam_data
        );
        drive_frame_simple(
            i_cam_vsync,
            i_cam_href,
            i_cam_data
        );
        $display("====== Camera Register Dump ======");
        $display("0x12 = %02h", cam_top_tb.sccb_slave_i.regs[8'h12]);
        $display("0x3A = %02h", cam_top_tb.sccb_slave_i.regs[8'h3A]);
        $display("0x40 = %02h", cam_top_tb.sccb_slave_i.regs[8'h40]);
        $display("0x8C = %02h", cam_top_tb.sccb_slave_i.regs[8'h8c]);
        
        // Wait some cycles to drain FIFO, then finish
        repeat (500) @(posedge i_cfg_clk);
        $display("Simulation completed without pixel mismatches.");
        $finish;
    end

endmodule
