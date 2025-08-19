`timescale 1ns/1ps

module RedPixelProcessingTop_tb;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam integer IMG_W = 640;
  localparam integer IMG_H = 480;
  localparam integer FRAMES_TO_SEND = 2;    // send 2 frames (one with red box, one blank black frame)
  localparam integer CLK_PERIOD_NS   = 10;  // 100 MHz

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
  logic [11:0] i_data;
  logic        i_almostempty;
  logic        o_rd_async_fifo;

  logic        i_obuf_rd;
  logic [11:0] o_obuf_data;
  logic [5:0]  o_obuf_fill;        
  logic        o_obuf_full;
  logic        o_obuf_almostfull;
  logic        o_obuf_empty;
  logic        o_obuf_almostempty;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  ProcessingTop #(
    .PROCESSING_LATENCY(12)
  ) dut (
    .i_clk             (i_clk),
    .i_rstn            (i_rstn),
    .i_flush           (i_flush),

    .i_data            (i_data),
    .i_almostempty     (i_almostempty),
    .o_rd_async_fifo   (o_rd_async_fifo),

    .i_obuf_rd         (i_obuf_rd),
    .o_obuf_data       (o_obuf_data),
    .o_obuf_fill       (o_obuf_fill),
    .o_obuf_full       (o_obuf_full),
    .o_obuf_almostfull (o_obuf_almostfull),
    .o_obuf_empty      (o_obuf_empty),
    .o_obuf_almostempty(o_obuf_almostempty)
  );

  // --------------------------------------------------------------------------
  // Test image generator
  // Frame 0: red box centered; Frame 1: blank
  // --------------------------------------------------------------------------
  function automatic [11:0] gen_pixel(input integer frame_id, input integer x, input integer y);
    if (frame_id == 0) begin
      if ((x >= 160 && x <= 480) && (y >= 120 && y <= 360))
        gen_pixel = 12'hF00;   // red
      else
        gen_pixel = 12'h000;   // black
    end else begin
      gen_pixel = 12'h000;     // black
    end
  endfunction

  // --------------------------------------------------------------------------
  // Producer: drive IMG_W*IMG_H pixels per frame
  // Handshake: present pixel, wait until DUT asserts o_rd_async_fifo, then advance
  // --------------------------------------------------------------------------
  task automatic drive_frame(input integer frame_id);
    integer i;
    integer x, y;

    i_almostempty = 0; // source has data

    for (i = 0; i < IMG_W*IMG_H; i = i + 1) begin
      x = i % IMG_W;
      y = i / IMG_W;

      i_data = gen_pixel(frame_id, x, y);

      // Wait until DUT pops the "camera FIFO"
      @(posedge i_clk);
      while (!o_rd_async_fifo) @(posedge i_clk);
    end

    // Source goes idle after the frame
    i_almostempty = 1;
  endtask

  // --------------------------------------------------------------------------
  // Consumer: read output FIFO continuously to avoid back-pressure stalls
  // --------------------------------------------------------------------------
  integer out_px_count;
  integer outfile;

  task automatic start_consumer();
    fork
      begin : CONSUMER_THREAD
        forever begin
          @(posedge i_clk);
          if (!o_obuf_empty) begin
            i_obuf_rd <= 1'b1;    // pop one word per cycle while data exists
            out_px_count = out_px_count + 1;
            $fdisplay(outfile, "%03h", o_obuf_data);
          end else begin
            i_obuf_rd <= 1'b0;
          end
        end
      end
    join_none
  endtask

  
  `ifdef DEBUG_PRINTS
    always @(posedge i_clk) if (rstn) begin
      if ($isunknown(o_rd_async_fifo))   $display("%t X: o_rd_async_fifo",   $time);
      if ($isunknown(o_obuf_empty))      $display("%t X: o_obuf_empty",      $time);
      if ($isunknown(o_obuf_almostfull)) $display("%t X: o_obuf_almostfull", $time);
    end
  `endif

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  logic [31:0] expected;
  logic [31:0] timeout_cycles;
  logic [31:0] cycles;

  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, RedPixelProcessingTop_tb);

    outfile = $fopen("output_pixels.txt", "w");

    // Reset
    i_data        = 12'h000;
    i_almostempty = 1;
    i_obuf_rd     = 0;
    out_px_count  = 0;

    i_rstn  = 0;
    i_flush = 0;
    repeat (10) @(posedge i_clk);
    i_rstn = 1;

    // Start consumer so back-pressure never stalls the pipe
    start_consumer();

    // Frame 0 (with red object)
    drive_frame(0);

    // Small gap
    repeat (20) 
    

    // Frame 1 (blank)
    drive_frame(1);

    // Drain and check
    expected       = IMG_W * IMG_H * FRAMES_TO_SEND;   // expect 2 frames worth of pixels
    timeout_cycles = (expected << 1) + 20000;          // generous timeout
    cycles         = 0;

    while ((out_px_count < expected) && (cycles < timeout_cycles)) begin
      @(posedge i_clk);
      cycles = cycles + 1;
    end

    $display("Output pixels produced: %0d (expected %0d)", out_px_count, expected);
    if (out_px_count != expected)
      $display("WARN: Did not receive full expected output before timeout.");

    $fclose(outfile);
    $finish;
  end

endmodule
