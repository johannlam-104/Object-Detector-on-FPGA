module centroidCalc #(
    parameter IMG_WIDTH       = 640,
    parameter IMG_HEIGHT      = 480,
    parameter PIXEL_THRESHOLD = 1000,
    parameter EOF_EARLY_BEATS = 5
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    input  wire [31:0] i_tdata,
    input  wire        i_tuser,
    input  wire        i_tlast,
    input  wire        i_tvalid,
    output wire        o_tready,

    output reg  [31:0] o_tdata,
    output reg         o_tvalid,
    output reg         o_tuser,
    output reg         o_tlast,
    input  wire        i_tready,

    output reg  [9:0]  o_centroid_x,
    output reg  [8:0]  o_centroid_y,
    output reg         o_red_object_valid,
    output reg         o_end_frame          // asserts EOF_EARLY_BEATS before true EOF
);

    // ----------------------------------------------------------------
    // Coordinate extraction (widths corrected)
    // ----------------------------------------------------------------
    wire [9:0] x_coor = i_tdata[18:9];   // 10 bits for width  up to 1024
    wire [8:0] y_coor = i_tdata[8:0];     // 9  bits for height up to 512
    wire       is_red = i_tdata[19];

    // ----------------------------------------------------------------
    // 1-deep register slice
    // ----------------------------------------------------------------
    assign o_tready = i_tready || !o_tvalid;
    wire fire_in  = i_tvalid && o_tready;
    wire fire_out = o_tvalid && i_tready;

    // ----------------------------------------------------------------
    // Early-EOF detection
    // Fires on the beat that is EOF_EARLY_BEATS before the last pixel.
    // Last pixel = (x == IMG_WIDTH-1, y == IMG_HEIGHT-1).
    // So early beat = x == (IMG_WIDTH-1 - EOF_EARLY_BEATS), same last line.
    // ----------------------------------------------------------------
    localparam EARLY_X = IMG_WIDTH - 1 - EOF_EARLY_BEATS;

    wire on_last_line  = (y_coor == IMG_HEIGHT - 1);
    wire early_eof_beat = fire_in && on_last_line && (x_coor == EARLY_X);
    wire true_eof_beat  = fire_in && on_last_line && i_tlast;

    // ----------------------------------------------------------------
    // Pass-through register - o_end_frame rides as a sideband
    // ----------------------------------------------------------------
    reg o_end_frame_next;  // combinational, loaded into output reg

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_tvalid     <= 1'b0;
            o_tuser      <= 1'b0;
            o_tlast      <= 1'b0;
            o_tdata      <= 0;
            o_end_frame  <= 1'b0;
        end else begin
            if (fire_in) begin
                o_tvalid    <= 1'b1;
                o_tuser     <= i_tuser;
                o_tlast     <= i_tlast;
                o_tdata     <= i_tdata;
                o_end_frame <= early_eof_beat;  // only high on that one beat
            end else if (fire_out && !fire_in) begin
                o_tvalid    <= 1'b0;
                o_end_frame <= 1'b0;            // clear when consumed
            end
        end
    end

    // ----------------------------------------------------------------
    // Accumulators - gate on fire_in
    // ----------------------------------------------------------------
    localparam XW = $clog2(IMG_WIDTH);
    localparam YW = $clog2(IMG_HEIGHT);

    reg [18:0]  red_pixel_counter;
    reg [XW-1:0] closest_x,  furthest_x;
    reg [YW-1:0] closest_y,  furthest_y;

    // Capture sum BEFORE clear so centroid latch sees correct values
    reg [XW:0] committed_sum_x;
    reg [YW:0] committed_sum_y;
    reg        committed_qualifies;

    wire [XW:0] sum_x = {1'b0, furthest_x} + {1'b0, closest_x};
    wire [YW:0] sum_y = {1'b0, furthest_y} + {1'b0, closest_y};
    wire red_object_qualifies = (red_pixel_counter >= PIXEL_THRESHOLD);

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            red_pixel_counter <= 0;
            closest_x  <= IMG_WIDTH  - 1;
            furthest_x <= 0;
            closest_y  <= IMG_HEIGHT - 1;
            furthest_y <= 0;
            committed_sum_x    <= 0;
            committed_sum_y    <= 0;
            committed_qualifies <= 0;
        end else if (true_eof_beat) begin
            // Snapshot THEN clear - centroid block reads committed_* next cycle
            committed_sum_x    <= sum_x;
            committed_sum_y    <= sum_y;
            committed_qualifies <= red_object_qualifies;

            red_pixel_counter <= 0;
            closest_x  <= IMG_WIDTH  - 1;
            furthest_x <= 0;
            closest_y  <= IMG_HEIGHT - 1;
            furthest_y <= 0;
        end else if (fire_in && is_red) begin
            red_pixel_counter <= red_pixel_counter + 1'b1;

            if ((y_coor < closest_y) || (y_coor == closest_y && x_coor < closest_x)) begin
                closest_x <= x_coor;
                closest_y <= y_coor;
            end
            if ((y_coor > furthest_y) || (y_coor == furthest_y && x_coor > furthest_x)) begin
                furthest_x <= x_coor;
                furthest_y <= y_coor;
            end
        end
    end

    // ----------------------------------------------------------------
    // Centroid latch - reads committed snapshot, one cycle after true EOF
    // ----------------------------------------------------------------
    reg early_eof_d1;
    always @(posedge i_clk) early_eof_d1 <= early_eof_beat;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_centroid_x       <= 0;
            o_centroid_y       <= 0;
            o_red_object_valid <= 0;
        end else if (early_eof_d1) begin
            o_centroid_x       <= committed_sum_x[XW:1];   // divide by 2
            o_centroid_y       <= committed_sum_y[YW:1];
            o_red_object_valid <= committed_qualifies;
        end
    end

endmodule
