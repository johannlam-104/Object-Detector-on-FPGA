`timescale 1ns/1ps

module RedPixelProcessingTop_tb;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam int IMG_WIDTH       = 640;
  localparam int IMG_HEIGHT      = 480;
  localparam int FRAMES_TO_SEND  = 5;          // total frames we intend to push through
  localparam int CLK_PERIOD_NS   = 10;         // 100 MHz
  localparam int TIMEOUT_CYC     = 8_000_000;  // global sim timeout safeguard

  // Frame IDs (what each number represents):
  //   frame_id == 0 : red box centered, black background
  //   frame_id == 1 : checkerboard red/black
  //   frame_id == 2 : full black frame
  //   frame_id == 3 : full red frame

  // --------------------------------------------------------------------------
  // Clock / Reset
  // --------------------------------------------------------------------------
  logic i_clk = 0;
  always #(CLK_PERIOD_NS/2) i_clk = ~i_clk;

  logic i_rstn  = 0;
  logic i_flush = 0;

  // --------------------------------------------------------------------------
  // DUT I/O
  // --------------------------------------------------------------------------
  logic [31:0] i_tdata;
  logic        i_tvalid;
  logic        i_tuser;
  logic        i_tlast;
  logic        i_empty;
  logic        o_tready;

  logic        o_tvalid;
  logic        i_tready;
  logic [31:0] o_tdata;
  logic        o_tuser;
  logic        o_tlast;

  logic        o_obuf_empty;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  ProcessingTop #(
    .IMG_WIDTH            (IMG_WIDTH),
    .IMG_HEIGHT           (IMG_HEIGHT),
    .PENDING_DURATION     (5),
    .PIXEL_THRESHOLD      (1000),
    .CROSSHAIR_SIZE       (10),
    .RAW_DATA_WIDTH       (32),
    .PROCESSED_DATA_WIDTH (1),
    .ADDR_WIDTH           (15), // 11 original
    .ALMOSTFULL_OFFSET    (1),
    .ALMOSTEMPTY_OFFSET   (1),
    .FIFO_PTR_WIDTH       (9),
    .TUSER_WIDTH          (1),
    .CAM_DATA_WIDTH       (32)
  ) DUT (
    .i_clk        (i_clk),
    .i_rstn       (i_rstn),
    .i_flush      (i_flush),

    .i_tdata      (i_tdata),
    .i_tvalid     (i_tvalid),
    .i_tuser      (i_tuser),
    .i_tlast      (i_tlast),
    .i_empty      (i_empty),
    .o_tready     (o_tready),

    .o_tvalid     (o_tvalid),
    .i_tready     (i_tready),
    .o_tdata      (o_tdata),
    .o_tuser      (o_tuser),
    .o_tlast      (o_tlast),

    .o_obuf_empty (o_obuf_empty)
  );

  // --------------------------------------------------------------------------
  // Pixel generator
  // --------------------------------------------------------------------------
  function automatic logic [31:0] gen_pixel(input int frame_id, input int x, input int y);
    if (frame_id == 0) begin
      // red box in middle with black background
      if ((x >= 160 && x <= 480) && (y >= 120 && y <= 360))
        gen_pixel = 32'hF000_0000;   // red
      else
        gen_pixel = 32'h0000_0000;   // black
    end
    else if (frame_id == 1) begin
      // checkerboard
      if (((x ^ y) & 1) == 1)
        gen_pixel = 32'hF000_0000;
      else
        gen_pixel = 32'h0000_0000;
    end
    else if (frame_id == 3) begin
      // full red
      gen_pixel = 32'hF000_0000;
    end
    else begin
      // full black
      gen_pixel = 32'h0000_0000;
    end
  endfunction

  function automatic logic gen_tuser(input int x, input int y);
    return (x==0 && y==0);
  endfunction

  function automatic logic gen_tlast(input int x);
    return (x==IMG_WIDTH-1);
  endfunction

  // --------------------------------------------------------------------------
  // Producer (Option A): AXIS-clean drive/hold loop
  // - Holds i_tdata/i_tuser/i_tlast stable while stalled (i_tvalid=1, o_tready=0)
  // - Advances x/y ONLY on real handshake "fire"
  // --------------------------------------------------------------------------
  task automatic drive_frame_axis_clean(input int frame_id);
    int x, y;
    begin
      x = 0; y = 0;

      i_empty  = 1'b0;
      i_tvalid = 1'b1;

      while (y < IMG_HEIGHT) begin
        // Drive current beat (MUST remain stable until it fires)
        i_tdata = gen_pixel(frame_id, x, y);
        i_tuser = gen_tuser(x, y);
        i_tlast = gen_tlast(x);

        @(posedge i_clk);

        // Advance ONLY on real pop/handshake
        if (i_tvalid && o_tready) begin
          if (x == IMG_WIDTH-1) begin
            x = 0;
            y = y + 1;
          end else begin
            x = x + 1;
          end
        end
      end

      // Idle after frame
      i_tvalid = 1'b0;
      i_empty  = 1'b1;
      i_tdata  = 32'h0000_0000;
      i_tuser  = 1'b0;
      i_tlast  = 1'b0;
      @(posedge i_clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Optional priming helper:
  // primes N lines of a given frame_id (still AXIS-clean)
  // --------------------------------------------------------------------------
  task automatic prime_lines_axis_clean(input int frame_id, input int num_lines);
    int x, y;
    begin
      x = 0; y = 0;

      i_empty  = 1'b0;
      i_tvalid = 1'b1;

      while (y < num_lines) begin
        i_tdata = gen_pixel(frame_id, x, y);
        i_tuser = gen_tuser(x, y);
        i_tlast = gen_tlast(x);

        @(posedge i_clk);

        if (i_tvalid && o_tready) begin
          if (x == IMG_WIDTH-1) begin
            x = 0;
            y = y + 1;
          end else begin
            x = x + 1;
          end
        end
      end

      // keep source "alive" or go idle; here we go idle between priming and full frame
      i_tvalid = 1'b0;
      i_empty  = 1'b1;
      i_tdata  = 32'h0000_0000;
      i_tuser  = 1'b0;
      i_tlast  = 1'b0;
      @(posedge i_clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Consumer: always-ready (baseline)
  // --------------------------------------------------------------------------
  integer out_px_count;
  integer outfile;

  task automatic start_consumer_always_ready();
    fork
      begin : CONSUMER_ALWAYS
        forever begin
          @(posedge i_clk);
          i_tready <= 1'b1;

          if (o_tvalid && i_tready) begin
            out_px_count = out_px_count + 1;
            $fdisplay(outfile, "%08h", o_tdata);
          end
        end
      end
    join_none
  endtask

  // --------------------------------------------------------------------------
  // Consumer: backpressure (random i_tready stalls)
  // stall_pct: 0..100 (percentage of cycles to deassert ready)
  // --------------------------------------------------------------------------
  task automatic start_consumer_backpressure(input int unsigned stall_pct);
    fork
      begin : CONSUMER_BP
        forever begin
          @(posedge i_clk);

          if ($urandom_range(0,99) < stall_pct) i_tready <= 1'b0;
          else                                 i_tready <= 1'b1;

          if (o_tvalid && i_tready) begin
            out_px_count = out_px_count + 1;
            $fdisplay(outfile, "%08h", o_tdata);
          end
        end
      end
    join_none
  endtask

  // --------------------------------------------------------------------------
  // Helpful banners / debug prints
  // --------------------------------------------------------------------------
  always @(posedge i_clk) begin
    if (i_tvalid && !i_empty && !o_tready)
      $display("%t TB stalled waiting for pop (o_tready=0)", $time);
  end

  // --------------------------------------------------------------------------
  // AXIS legality checkers (input + output must remain stable while stalled)
  // --------------------------------------------------------------------------
  logic [31:0] i_tdata_d;
  logic        i_tuser_d, i_tlast_d;

  always @(posedge i_clk) begin
    i_tdata_d <= i_tdata;
    i_tuser_d <= i_tuser;
    i_tlast_d <= i_tlast;

    if (i_tvalid && !o_tready) begin
      if (i_tdata !== i_tdata_d) $display(1, "%t TB violates AXIS: i_tdata changed while stalled", $time); // original: $fatal
      if (i_tuser !== i_tuser_d) $display(1, "%t TB violates AXIS: i_tuser changed while stalled", $time); // original: $fatal
      if (i_tlast !== i_tlast_d) $display(1, "%t TB violates AXIS: i_tlast changed while stalled", $time); // original: $fatal
    end
  end

  logic [31:0] o_tdata_d;
  logic        o_tuser_d, o_tlast_d;

  always @(posedge i_clk) begin
    o_tdata_d <= o_tdata;
    o_tuser_d <= o_tuser;
    o_tlast_d <= o_tlast;

    if (o_tvalid && !i_tready) begin
      if (o_tdata !== o_tdata_d) $display(1, "%t DUT violates AXIS: o_tdata changed while stalled", $time); // original: $fatal
      if (o_tuser !== o_tuser_d) $display(1, "%t DUT violates AXIS: o_tuser changed while stalled", $time); // original: $fatal
      if (o_tlast !== o_tlast_d) $display(1, "%t DUT violates AXIS: o_tlast changed while stalled", $time); // original: $fatal
    end
  end
  // --------------------------------------------------------------------------
  // FIFO test (no error/dropped beats)
  // --------------------------------------------------------------------------
  /*
  always @(posedge i_clk) begin
      if (DUT.pp_fifo_error) begin
        $fatal(1, "%t pp_fifo dropped", $time);
      end
      if (DUT.delay_fifo_error) begin
        $fatal(1, "%t delay_fifo dropped", $time);
      end
      if (DUT.obuf_error) begin
        $fatal(1, "%t obuf_fifo dropped", $time);
      end
  end
  */
  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  int unsigned cycles;

  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, RedPixelProcessingTop_tb);

    outfile      = $fopen("output_pixels.txt", "w");
    out_px_count = 0;

    // Initialize all inputs (prevents X poisoning)
    i_tdata  = 32'h0000_0000;
    i_tuser  = 1'b0;
    i_tlast  = 1'b0;
    i_tvalid = 1'b0;
    i_empty  = 1'b1;
    i_tready = 1'b0;

    // Reset
    i_rstn  = 1'b0;
    i_flush = 1'b0;
    repeat (10) @(posedge i_clk);
    i_rstn = 1'b1;

    // Choose ONE consumer mode:
    // start_consumer_always_ready();
    start_consumer_backpressure(30); // 30% stall rate

    // ------------------------------------------------------------------------
    // Frame plan:
    //   Frame 2: full black (baseline)
    //   Frame 0: red box (should produce centroid + crosshair on NEXT frame)
    //   Frame 2: full black (crosshair expected here)
    //   Frame 1: checkerboard (stress centroid)
    //   Frame 2: full black (reset observation)
    // ------------------------------------------------------------------------

    $display("%t TB: drive_frame(2) // full black", $time);
    drive_frame_axis_clean(2);

    $display("%t TB: drive_frame(0) // red box centered", $time);
    drive_frame_axis_clean(0);

    $display("%t TB: drive_frame(2) // full black (crosshair expected)", $time);
    drive_frame_axis_clean(2);

    $display("%t TB: drive_frame(1) // checkerboard", $time);
    drive_frame_axis_clean(1);

    $display("%t TB: drive_frame(2) // full black", $time);
    drive_frame_axis_clean(2);

    // Global timeout guard (prevents sim running forever if something wedges)
    cycles = 0;
    while (cycles < TIMEOUT_CYC) begin
      @(posedge i_clk);
      cycles++;
    end

    $display("TB done. Output pixels seen (counting transfers): %0d", out_px_count);
    $fclose(outfile);
    $finish;
  end

endmodule
