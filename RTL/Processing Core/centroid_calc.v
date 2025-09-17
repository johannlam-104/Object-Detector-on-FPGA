`timescale 1ns / 1ps



module centroidCalc #(
    parameter IMG_WIDTH = 640,
    parameter IMG_HEIGHT = 480,
    parameter PIXEL_THRESHOLD = 1000 // minimum amount of red pixels to be considered valid object
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    input  wire        i_valid_red_pixel,
    input  wire        i_px_valid,

    output reg  [9:0]  o_centroid_x,
    output reg  [8:0]  o_centroid_y,
    output reg         o_px_valid,
    output reg         o_red_object_valid,
    
    output reg         o_end_frame,
    output reg         o_eof_valid
    
);

    localparam X_WIDTH = $clog2(IMG_WIDTH);
    localparam Y_WIDTH = $clog2(IMG_HEIGHT);

    reg [X_WIDTH:0] x_counter;
    reg [Y_WIDTH:0] y_counter;

    reg [X_WIDTH:0] closest_x, furthest_x;
    reg [Y_WIDTH:0] closest_y, furthest_y;
    reg [18:0]   red_pixel_counter;

    wire at_last_pixel = (x_counter == IMG_WIDTH - 1) && (y_counter == IMG_HEIGHT - 1);
    wire commit = at_last_pixel && i_px_valid;
    
    // end frame logic
    reg end_frame;
    

    // counters
    always @(posedge i_clk) begin
        if (~i_rstn || end_frame) begin
            x_counter <= 0;
            y_counter <= 0;
        end 
        else if (i_px_valid) begin
            x_counter <= (x_counter == IMG_WIDTH-1) ? 0 : x_counter + 1'b1;
            y_counter <= (x_counter == IMG_WIDTH-1) ? y_counter + 1'b1 : y_counter;
        end
    end

    // End-frame flag
    always @(posedge i_clk) begin
        if (~i_rstn)begin
            o_end_frame <= 0;
            o_eof_valid <= 0;
        end
        else begin
            o_eof_valid <= commit;
            o_end_frame <= commit; // original: end_frame_sync
        end
    end
    
    
    // Red pixel accumulation
    always @(posedge i_clk) begin
        if (~i_rstn || commit) begin
            red_pixel_counter <= 0;
            closest_x <= IMG_WIDTH - 1;
            closest_y <= IMG_HEIGHT - 1;
            furthest_x <= 0;
            furthest_y <= 0;
        end 
        else if (i_px_valid && i_valid_red_pixel) begin
            red_pixel_counter <= red_pixel_counter + 1;
            if (y_counter < closest_y || (y_counter == closest_y && x_counter < closest_x)) begin // upper left most red pixel
                closest_x <= x_counter;
                closest_y <= y_counter;
            end
            if (y_counter > furthest_y || (y_counter == furthest_y && x_counter > furthest_x)) begin // lowest right most pixel
                furthest_x <= x_counter;
                furthest_y <= y_counter;
            end
        end
    end
    
    wire red_object_qualifies = (red_pixel_counter >= PIXEL_THRESHOLD); // if my object is big enough
    
    // Output division results
    always @(posedge i_clk) begin
        if (~i_rstn) begin
            o_centroid_x <= 0;
            o_centroid_y <= 0;
            o_px_valid <= 0;
            o_red_object_valid <= 0;
            end_frame <= 0;
        end 
        else if (commit) begin
            o_centroid_x <= red_object_qualifies ? (furthest_x + closest_x) >> 1 : 0;
            o_centroid_y <= red_object_qualifies ? (furthest_y + closest_y) >> 1 : 0;
            o_px_valid <= 1'b1;
            o_red_object_valid <= red_object_qualifies ? 1'b1 : 0;
            end_frame <= 1'b1;
        end
        else if(i_px_valid)begin
            o_centroid_x <= 0;
            o_centroid_y <= 0;
            o_px_valid <= 1'b1;
            o_red_object_valid <= 0;
            end_frame <= 0;
        end
        else begin
            end_frame <= 0;
            o_px_valid <= 0;
            o_red_object_valid <= 0;
        end
    end
endmodule

