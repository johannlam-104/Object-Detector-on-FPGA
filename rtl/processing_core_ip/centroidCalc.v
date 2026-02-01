/*
`timescale 1ns/1ps
module centroidCalc #(
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480,
    parameter PIXEL_THRESHOLD = 1000
)(
    input  wire        i_clk,
    input  wire        i_rstn,
    
    // write side
    input  wire        i_tdata,             // filtered red flag (per pixel)
    input  wire        i_tuser,
    input  wire        i_tlast,
    input  wire        i_tvalid,            // per-pixel enable (same beat as x/y)
    output wire        o_tready,
    
    // read side
    output reg         o_tvalid,
    output reg         o_tuser,     // I'll expose this signal for debugging and alignment
    output reg         o_tlast,
    input  wire        i_tready,
    
    // metadata to overlay
    output reg  [9:0]  o_centroid_x,
    output reg  [8:0]  o_centroid_y,
    output reg         o_red_object_valid,  // level: result of last commit
    output reg         o_end_frame          // 1-cycle pulse at frame boundary
);
    
    assign o_tready = 1'b1; // always high, no backpressure in this module
    
    wire in_xfer = i_tvalid;
    
    wire out_xfer = o_tvalid && i_tready;
    
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_tvalid <= 1'b0;
            o_tuser  <= 1'b0;
            o_tlast  <= 1'b0;
        end else begin
            // If output is free (or being consumed), we can load a new beat.
            if (!o_tvalid || i_tready) begin
                o_tvalid <= in_xfer;
                o_tuser  <= i_tuser;
                o_tlast  <= i_tlast;
            end
            // else hold while stalled
        end
    end

    // ----------------------------------------------------------------
    // Raster + EOF pulse (all synchronous)
    // ----------------------------------------------------------------
    localparam XW = $clog2(IMG_WIDTH);
    localparam YW = $clog2(IMG_HEIGHT);

    reg [XW-1:0] x_counter;
    reg [YW-1:0] y_counter;

    wire valid = in_xfer; // accepted pixel

    wire last_x = (x_counter == IMG_WIDTH-1);
    wire last_y = (y_counter == IMG_HEIGHT-1);

    wire commit_pulse_next = valid && last_x && last_y;

    // Your early publish (keep if you want)
    wire publish = valid && (x_counter == IMG_WIDTH-6) && (y_counter == IMG_HEIGHT-1);

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            x_counter <= 0;
            y_counter <= 0;
        end else if (valid) begin
            if (last_x) begin
                x_counter <= 0;
                y_counter <= last_y ? 0 : (y_counter + 1'b1);
            end else begin
                x_counter <= x_counter + 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Accumulators / bounding box over valid red pixels
    // ----------------------------------------------------------------
     reg [18:0]   red_pixel_counter;
    reg [XW-1:0] closest_x,  furthest_x;
    reg [YW-1:0] closest_y,  furthest_y;

    wire [XW:0] sum_x = {1'b0, furthest_x} + {1'b0, closest_x};
    wire [YW:0] sum_y = {1'b0, furthest_y} + {1'b0, closest_y};

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            red_pixel_counter <= 0;
            closest_x <= IMG_WIDTH-1;
            furthest_x <= 0;
            closest_y <= IMG_HEIGHT-1;
            furthest_y <= 0;
        end else if (commit_pulse_next) begin
            red_pixel_counter <= 0;
            closest_x <= IMG_WIDTH-1;
            furthest_x <= 0;
            closest_y <= IMG_HEIGHT-1;
            furthest_y <= 0;
        end else if (valid && i_tdata) begin
            red_pixel_counter <= red_pixel_counter + 1'b1;

            if ((y_counter < closest_y) || ((y_counter == closest_y) && (x_counter < closest_x))) begin
                closest_x <= x_counter;
                closest_y <= y_counter;
            end
            if ((y_counter > furthest_y) || ((y_counter == furthest_y) && (x_counter > furthest_x))) begin
                furthest_x <= x_counter;
                furthest_y <= y_counter;
            end
        end
    end

    wire red_object_qualifies = (red_pixel_counter >= PIXEL_THRESHOLD);

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_end_frame        <= 1'b0;
            o_red_object_valid <= 1'b0;
            o_centroid_x       <= 10'd0;
            o_centroid_y       <= 9'd0;
        end else begin
            o_end_frame <= publish;

            if (publish) begin
                o_centroid_x       <= (sum_x >> 1);
                o_centroid_y       <= (sum_y >> 1);
                o_red_object_valid <= red_object_qualifies;
            end
        end
    end

endmodule
*/

module centroidCalc #(
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480,
    parameter PIXEL_THRESHOLD = 1000
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // write side
    input  wire        i_tdata,
    input  wire        i_tuser,
    input  wire        i_tlast,
    input  wire        i_tvalid,
    output wire        o_tready,

    // read side (pass-through stream for alignment/debug)
    output reg         o_tvalid,
    output reg         o_tuser,
    output reg         o_tlast,
    input  wire        i_tready,

    // metadata to overlay
    output reg  [9:0]  o_centroid_x,
    output reg  [8:0]  o_centroid_y,
    output reg         o_red_object_valid,
    output reg         o_end_frame
);

    // 1-deep register slice semantics
    assign o_tready = i_tready || !o_tvalid;
    wire fire = i_tvalid && o_tready;   // we accepted a beat

    // Pass-through regs (ONLY update when we accept)
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_tvalid <= 1'b0;
            o_tuser  <= 1'b0;
            o_tlast  <= 1'b0;
        end else if (o_tready) begin
            o_tvalid <= i_tvalid;
            if (i_tvalid) begin
                o_tuser <= i_tuser;
                o_tlast <= i_tlast;
            end
        end
    end

    // ---- raster/counters should advance only on fire ----
    localparam XW = $clog2(IMG_WIDTH);
    localparam YW = $clog2(IMG_HEIGHT);

    reg [XW-1:0] x_counter;
    reg [YW-1:0] y_counter;

    wire last_x = (x_counter == IMG_WIDTH-1);
    wire last_y = (y_counter == IMG_HEIGHT-1);

    // You wanted early publish relative to "end-of-frame".
    // BUT do not key this off free-running counters; key it off accepted beats.
    wire publish = fire && (y_counter == IMG_HEIGHT-1) && (x_counter == IMG_WIDTH-1-5);

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            x_counter <= 0;
            y_counter <= 0;
        end else if (fire) begin
            if (i_tuser) begin
                // trust metadata for frame start
                x_counter <= 0;
                y_counter <= 0;
            end else if (last_x) begin
                x_counter <= 0;
                y_counter <= last_y ? 0 : (y_counter + 1'b1);
            end else begin
                x_counter <= x_counter + 1'b1;
            end
        end
    end

    // your bbox accumulators: also gate with fire
    reg [18:0] red_pixel_counter;
    reg [XW-1:0] closest_x, furthest_x;
    reg [YW-1:0] closest_y, furthest_y;

    wire [XW:0] sum_x = {1'b0, furthest_x} + {1'b0, closest_x};
    wire [YW:0] sum_y = {1'b0, furthest_y} + {1'b0, closest_y};
    wire red_object_qualifies = (red_pixel_counter >= PIXEL_THRESHOLD);

    // commit at true EOF (use i_tuser to reset, and use last_x/last_y on fire)
    wire eof = fire && last_x && last_y;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            red_pixel_counter <= 0;
            closest_x <= IMG_WIDTH-1;
            furthest_x <= 0;
            closest_y <= IMG_HEIGHT-1;
            furthest_y <= 0;
        end else if (eof) begin
            // clear at end of frame
            red_pixel_counter <= 0;
            closest_x <= IMG_WIDTH-1;
            furthest_x <= 0;
            closest_y <= IMG_HEIGHT-1;
            furthest_y <= 0;
        end else if (fire && i_tdata) begin
            red_pixel_counter <= red_pixel_counter + 1'b1;
            if ((y_counter < closest_y) || ((y_counter == closest_y) && (x_counter < closest_x))) begin
                closest_x <= x_counter;
                closest_y <= y_counter;
            end
            if ((y_counter > furthest_y) || ((y_counter == furthest_y) && (x_counter > furthest_x))) begin
                furthest_x <= x_counter;
                furthest_y <= y_counter;
            end
        end
    end

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_end_frame        <= 1'b0;
            o_red_object_valid <= 1'b0;
            o_centroid_x       <= 0;
            o_centroid_y       <= 0;
        end else begin
            o_end_frame <= publish;   // 1-cycle pulse

            if (publish) begin
                o_centroid_x       <= (sum_x >> 1);
                o_centroid_y       <= (sum_y >> 1);
                o_red_object_valid <= red_object_qualifies;
            end
        end
    end

endmodule

/*
module centroidCalc #(
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480,
    parameter PIXEL_THRESHOLD = 1000
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // write side
    input  wire        i_tdata,   // 1-bit red flag
    input  wire        i_tuser,   // SOF (1 on first pixel of frame)
    input  wire        i_tlast,   // EOL (1 on last pixel of line)
    input  wire        i_tvalid,
    output wire        o_tready,

    // read side (pass-through stream for alignment/debug)
    output reg         o_tvalid,
    output reg         o_tuser,
    output reg         o_tlast,
    input  wire        i_tready,

    // metadata to overlay (for NEXT frame)
    output reg  [9:0]  o_centroid_x,
    output reg  [8:0]  o_centroid_y,
    output reg         o_red_object_valid,
    output reg         o_end_frame          // 1-cycle pulse at true EOF (handshake)
);

    // -------------------------------------------------------------------------
    // One source of truth: advance ONLY on handshake
    // -------------------------------------------------------------------------
    assign o_tready = i_tready || !o_tvalid;

    wire fire_in  = i_tvalid && o_tready;   // accepted input beat
    wire fire_out = o_tvalid && i_tready;   // output beat consumed

    // -------------------------------------------------------------------------
    // Pass-through elastic register (bubble-safe)
    // Holds {user,last} stable while stalled, never overwrites an unconsumed beat.
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_tvalid <= 1'b0;
            o_tuser  <= 1'b0;
            o_tlast  <= 1'b0;
        end else begin
            if (fire_in) begin
                o_tvalid <= 1'b1;
                o_tuser  <= i_tuser;
                o_tlast  <= i_tlast;
            end else if (fire_out) begin
                o_tvalid <= 1'b0;
            end
            // else: hold stable
        end
    end

    // -------------------------------------------------------------------------
    // Raster counters driven by metadata (SOF/EOL), not by free-running width.
    // This makes you tolerant to bubbles and avoids relying on IMG_WIDTH "perfect".
    // -------------------------------------------------------------------------
    localparam XW = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH);
    localparam YW = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);

    reg [XW-1:0] x_counter;
    reg [YW-1:0] y_counter;

    wire last_y = (y_counter == IMG_HEIGHT-1);

    // true end-of-frame = last line's EOL beat accepted
    wire eof = fire_in && i_tlast && last_y;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            x_counter <= {XW{1'b0}};
            y_counter <= {YW{1'b0}};
        end else if (fire_in) begin
            if (i_tuser) begin
                // frame start: trust SOF
                x_counter <= {XW{1'b0}};
                y_counter <= {YW{1'b0}};
            end else begin
                // advance x each accepted pixel
                if (x_counter != IMG_WIDTH-1)
                    x_counter <= x_counter + {{(XW-1){1'b0}},1'b1};
                else
                    x_counter <= {XW{1'b0}};

                // advance y only on accepted EOL
                if (i_tlast) begin
                    if (y_counter != IMG_HEIGHT-1)
                        y_counter <= y_counter + {{(YW-1){1'b0}},1'b1};
                    else
                        y_counter <= {YW{1'b0}};
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Bounding-box accumulators (gate everything with fire_in)
    // -------------------------------------------------------------------------
    // red pixel count needs up to 640*480 = 307200 < 2^19
    reg [18:0]   red_pixel_counter;
    reg [XW-1:0] closest_x,  furthest_x;
    reg [YW-1:0] closest_y,  furthest_y;

    wire [XW:0] sum_x = {1'b0, furthest_x} + {1'b0, closest_x};
    wire [YW:0] sum_y = {1'b0, furthest_y} + {1'b0, closest_y};

    wire red_object_qualifies = (red_pixel_counter >= PIXEL_THRESHOLD);

    // helper constants with correct widths
    wire [XW-1:0] X_MAX = IMG_WIDTH-1;
    wire [YW-1:0] Y_MAX = IMG_HEIGHT-1;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            red_pixel_counter <= 19'd0;
            closest_x         <= X_MAX;
            furthest_x        <= {XW{1'b0}};
            closest_y         <= Y_MAX;
            furthest_y        <= {YW{1'b0}};
        end else begin
            // reset accumulators at SOF (accepted) so frame boundaries are explicit
            if (fire_in && i_tuser) begin
                red_pixel_counter <= 19'd0;
                closest_x         <= X_MAX;
                furthest_x        <= {XW{1'b0}};
                closest_y         <= Y_MAX;
                furthest_y        <= {YW{1'b0}};
            end else if (fire_in && i_tdata) begin
                red_pixel_counter <= red_pixel_counter + 19'd1;

                // top-left-ish: smallest y, then smallest x
                if ((y_counter < closest_y) || ((y_counter == closest_y) && (x_counter < closest_x))) begin
                    closest_x <= x_counter;
                    closest_y <= y_counter;
                end

                // bottom-right-ish: largest y, then largest x
                if ((y_counter > furthest_y) || ((y_counter == furthest_y) && (x_counter > furthest_x))) begin
                    furthest_x <= x_counter;
                    furthest_y <= y_counter;
                end
            end

            // optional: you can also clear on eof instead of SOF; SOF-reset is safer under bubbles
            // if (eof) begin ... end
        end
    end

    // -------------------------------------------------------------------------
    // Publish outputs at true EOF (handshake on last line EOL)
    // This guarantees 1-frame latency without fragile "early publish" offsets.
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_end_frame        <= 1'b0;
            o_red_object_valid <= 1'b0;
            o_centroid_x       <= 10'd0;
            o_centroid_y       <= 9'd0;
        end else begin
            o_end_frame <= eof; // 1-cycle pulse

            if (eof) begin
                // centroid = midpoint of bbox
                o_centroid_x       <= sum_x[XW:1];  // >>1, truncated
                o_centroid_y       <= sum_y[YW:1];
                o_red_object_valid <= red_object_qualifies;
            end
        end
    end
endmodule
*/

