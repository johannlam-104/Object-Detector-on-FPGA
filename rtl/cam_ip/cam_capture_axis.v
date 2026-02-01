// capture.v
// OV7670 capture (PCLK domain) -> async FIFO write side
//
// - Packs RGB565 from two 8-bit camera bytes into a 16-bit pixel.
// - Appends 2 bits of metadata for video AXI-Stream style framing:
//     {pixel[15:0], tuser_sof, tlast_eol}  => 18 bits total
// - Uses fixed 640x480 framing:
//     * SOF (tuser[0]) asserted on the FIRST pixel written after SOF edge
//     * EOL (tlast) asserted on pixel x==639 (last pixel of each active line)
// - "Lossless" requires the downstream FIFO never asserts full. If full does
//   happen, this module will drop pixels and raise o_overflow (sticky).
//
// Notes:
// - Camera cannot be backpressured; always track byte packing on PCLK.
// - Only advance x/y counters when we successfully write into the FIFO.
module cam_capture_axis
(
    input  wire        i_pclk,     // camera pixel clock
    input  wire        i_rstn,     // synchronous active-low reset
    input  wire        i_cfg_done, // cam config done flag
    output wire        o_status,   // asserted when capturing

    // OV7670 camera interface
    input  wire        i_vsync,    // frame timing (polarity depends on config)
    input  wire        i_href,     // active-high during active line pixels
    input  wire [7:0]  i_data,     // byte stream

    // Async FIFO write interface (ready/valid style)
    output reg         o_mvalid,   // FIFO write enable (pulse for each pixel beat)
    output reg  [33:0] o_tdata,    // {pixel[15:0], 16'h0000, sof, eol}
    input  wire        i_sready,   // FIFO can accept write (i.e., !full)

    // Debug
    output reg         o_overflow  // sticky if FIFO not-ready when a pixel beat occurs
);

    // -----------------------------
    // Params (fixed VGA)
    // -----------------------------
    localparam integer ACTIVE_W = 640;
    localparam integer ACTIVE_H = 480;

    // -----------------------------
    // FSM encoding 
    // -----------------------------
    reg [1:0] STATE, NEXT_STATE;
    localparam STATE_IDLE    = 2'd0,
               STATE_ACTIVE  = 2'd1,
               STATE_INITIAL = 2'd2;

    assign o_status = (STATE == STATE_ACTIVE);

    // -----------------------------
    // VSYNC edge detect (2FF)
    // -----------------------------
    reg  vsync1, vsync2;
    wire sof_edge;
    wire vsync_posedge;

    always @(posedge i_pclk) begin
        if(!i_rstn) begin
            {vsync1, vsync2} <= 2'b00;
        end 
        else begin
            vsync1 <= i_vsync;
            vsync2 <= vsync1;
        end
    end

    assign sof_edge     = (vsync2 == 1'b1) && (vsync1 == 1'b0); // falling edge
    assign vsync_posedge= (vsync2 == 1'b0) && (vsync1 == 1'b1); // rising edge

    // -----------------------------
    // Byte packer state
    // -----------------------------
    reg [7:0]  byte1_data, nxt_byte1_data;
    reg        pixel_half, nxt_pixel_half; // 0=expect first byte, 1=expect second byte

    // -----------------------------
    // Counters + SOF pending
    // -----------------------------
    reg  [9:0]  x, nxt_x;      // 0..639
    reg  [8:0]  y, nxt_y;      // 0..479
    reg         sof_pending, nxt_sof_pending;

    // -----------------------------
    // Next outputs
    // -----------------------------
    reg        nxt_wr;
    reg [33:0] nxt_tdata; // {pixel[15:0], 16'h0000, sof, eol}
    reg        nxt_overflow;

    // -----------------------------
    // Helpers
    // -----------------------------
    wire at_last_pix = (x >= (ACTIVE_W-1));          // current x refers to "next pixel to write"
    wire at_last_row = (y >= (ACTIVE_H-1));

    // A pixel beat is *formed* when we see the second byte while HREF=1 in ACTIVE.
    wire pixel_formed = (STATE == STATE_ACTIVE) && i_href && pixel_half;

    // A pixel beat is *accepted into FIFO* when we assert write and FIFO is ready.
    // Only assert o_mvalid when we have a pixel and i_sready is high,
    // so "fire" is effectively (pixel_formed && i_sready).
    wire fire = pixel_formed && i_sready;

    // EOL should tag the beat that is the last pixel of the line (x==639) *when that beat is written*
    wire eol_this = at_last_pix;

    // SOF should tag the first beat written after SOF edge
    wire sof_this = sof_pending;

    // -----------------------------
    // Next-state combinational logic
    // -----------------------------
    always @* begin
        // defaults
        NEXT_STATE       = STATE;

        nxt_wr           = 1'b0;
        nxt_tdata        = o_tdata;

        nxt_byte1_data   = byte1_data;
        nxt_pixel_half   = pixel_half;

        nxt_x            = x;
        nxt_y            = y;

        nxt_sof_pending  = sof_pending;
        nxt_overflow     = o_overflow;

        case (STATE)
            STATE_INITIAL: begin
                // Wait for config done and a clean SOF to start
                nxt_pixel_half  = 1'b0;
                nxt_x           = 10'd0;
                nxt_y           = 9'd0;
                nxt_sof_pending = 1'b0;

                if (i_cfg_done && sof_edge) begin
                    NEXT_STATE       = STATE_IDLE;
                    nxt_sof_pending  = 1'b1;   // tag first pixel that gets written
                    nxt_x            = 10'd0;
                    nxt_y            = 9'd0;
                end
            end

            STATE_IDLE: begin
                // Not capturing pixels yet; wait for SOF to enter ACTIVE
                nxt_wr          = 1'b0;
                nxt_pixel_half  = 1'b0;
                nxt_x           = 10'd0;
                nxt_y           = 9'd0;

                if (sof_edge) begin
                    NEXT_STATE       = STATE_ACTIVE;
                    nxt_sof_pending  = 1'b1;
                    nxt_x            = 10'd0;
                    nxt_y            = 9'd0;
                end
            end

            STATE_ACTIVE: begin
                // If we see SOF edge while active, restart framing (robust re-lock)
                if (sof_edge) begin
                    nxt_sof_pending = 1'b1;
                    nxt_x           = 10'd0;
                    nxt_y           = 9'd0;
                    nxt_pixel_half  = 1'b0; // re-align packer at frame boundary
                end

                // Reset half toggle when HREF drops (blanking between lines)
                if (!i_href) begin
                    nxt_wr         = 1'b0;
                    nxt_pixel_half = 1'b0;
                end 
                else begin
                    // While HREF=1, consume bytes
                    if (!pixel_half) begin
                        // First byte
                        nxt_byte1_data = i_data;
                        nxt_wr         = 1'b0;
                        nxt_pixel_half = 1'b1;
                    end 
                    else begin
                        // Second byte -> pixel formed this cycle
                        if (i_sready && (y < ACTIVE_H)) begin
                            // We will successfully write: assert valid and provide data+meta
                            nxt_wr    = 1'b1;
                            nxt_tdata = {i_data[7:0], byte1_data[7:0], 16'h0000, sof_this, eol_this};

                            // Consume SOF only when the tagged beat is actually written
                            if (sof_pending)
                                nxt_sof_pending = 1'b0;

                            // Advance x/y ONLY on accepted write (we ensured i_sready here)
                            if (eol_this) begin
                                nxt_x = 10'd0;
                                if (!at_last_row)
                                    nxt_y = y + 1'b1;
                                else
                                    nxt_y = y; // stop after last row; wait for next SOF
                            end 
                            else begin
                                nxt_x = x + 1'b1;
                            end
                        end 
                        else begin
                            // FIFO not ready (or we already have full frame): must drop
                            // (camera cannot stall)
                            nxt_wr       = 1'b0;
                            nxt_overflow = 1'b1;
                            // Do NOT advance x/y, do NOT consume sof_pending
                        end

                        // Regardless, the packer must move back to first-byte phase
                        nxt_pixel_half = 1'b0;
                    end
                end

                if (vsync_posedge) begin
                    NEXT_STATE      = STATE_IDLE;
                    nxt_pixel_half  = 1'b0;
                end
            end

            default: begin
                NEXT_STATE = STATE_INITIAL;
            end
        endcase
    end

    // -----------------------------
    // Sequential register update
    // -----------------------------
    always @(posedge i_pclk) begin
        if(!i_rstn) begin
            o_mvalid      <= 1'b0;
            o_tdata       <= 14'd0;
            o_overflow    <= 1'b0;

            byte1_data    <= 8'd0;
            pixel_half    <= 1'b0;

            x             <= 10'd0;
            y             <= 9'd0;

            sof_pending   <= 1'b0;

            STATE         <= STATE_INITIAL;
        end 
        else begin
            o_mvalid      <= nxt_wr;
            o_tdata       <= nxt_tdata;
            o_overflow    <= nxt_overflow;

            byte1_data    <= nxt_byte1_data;
            pixel_half    <= nxt_pixel_half;

            x             <= nxt_x;
            y             <= nxt_y;

            sof_pending   <= nxt_sof_pending;

            STATE         <= NEXT_STATE;
        end
    end

endmodule
