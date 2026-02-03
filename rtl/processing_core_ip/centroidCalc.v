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

    // early to account for pending period in overlay
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

    //  bbox accumulators: also gate with fire
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
