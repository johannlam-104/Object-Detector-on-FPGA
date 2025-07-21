`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/07/2025 11:17:24 PM
// Design Name: 
// Module Name: centroidCalc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module centroidCalc #(
    parameter IMG_WIDTH = 640,
    parameter IMG_HEIGHT = 480,
    parameter PIXEL_THRESHOLD = 1000,
    parameter DENSITY_THRESHOLD = 40  // in percent, no decimal
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    input  wire        i_valid_red_pixel,
    input  wire        i_valid,

    output reg  [9:0]  centroid_x,
    output reg  [8:0]  centroid_y,
    output reg         valid,
    output reg         red_object_valid,
    output reg         end_frame
);

    // Compute required bit widths
    localparam X_WIDTH = $clog2(IMG_WIDTH);
    localparam Y_WIDTH = $clog2(IMG_HEIGHT);

    // Position trackers
    reg [X_WIDTH-1:0] x_counter;
    reg [Y_WIDTH-1:0] y_counter;

    // Bounding box and centroid accumulation
    reg [X_WIDTH-1:0] closest_x, furthest_x;
    reg [Y_WIDTH-1:0] closest_y, furthest_y;
    reg [18:0]        red_pixel_counter;
    reg [31:0]        sum_x, sum_y;
    reg               end_frame_d;

    // Main position tracker
    always @(posedge i_clk) begin
        if (~i_rstn) begin
            x_counter <= 0;
            y_counter <= 0;
            end_frame <= 0;
        end else if (i_valid) begin
            if (x_counter == IMG_WIDTH - 1) begin
                x_counter <= 0;
                if (y_counter == IMG_HEIGHT - 1) begin
                    y_counter <= 0;
                    end_frame <= 1;
                end else begin
                    y_counter <= y_counter + 1;
                    end_frame <= 0;
                end
            end else begin
                x_counter <= x_counter + 1;
                end_frame <= 0;
            end
        end else begin
            end_frame <= 0;
        end
    end
    
    always@(posedge i_clk)begin
        if(~i_rstn)
            end_frame_d <= 0;
        else
            end_frame_d <= end_frame;
    end

    // Accumulate red pixel stats
    always @(posedge i_clk) begin
        if (~i_rstn || end_frame_d) begin
            red_pixel_counter <= 0;
            sum_x <= 0;
            sum_y <= 0;
            closest_x <= IMG_WIDTH - 1;
            closest_y <= IMG_HEIGHT - 1;
            furthest_x <= 0;
            furthest_y <= 0;
        end else if (i_valid && i_valid_red_pixel) begin
            red_pixel_counter <= red_pixel_counter + 1;
            sum_x <= sum_x + x_counter;
            sum_y <= sum_y + y_counter;

            // Closest red pixel to top-left
            if (y_counter < closest_y || (y_counter == closest_y && x_counter < closest_x)) begin
                closest_x <= x_counter;
                closest_y <= y_counter;
            end

            // Furthest red pixel from top-left
            if (y_counter > furthest_y || (y_counter == furthest_y && x_counter > furthest_x)) begin
                furthest_x <= x_counter;
                furthest_y <= y_counter;
            end
        end
    end

    // Final density and centroid calculation
    wire [X_WIDTH:0] box_width  = furthest_x - closest_x + 1;
    wire [Y_WIDTH:0] box_height = furthest_y - closest_y + 1;
    wire [31:0] area = box_width * box_height;

    wire [31:0] scaled_red  = red_pixel_counter * 100;
    wire [31:0] scaled_area = area * DENSITY_THRESHOLD;

    always @(posedge i_clk) begin
        if (~i_rstn) begin
            red_object_valid <= 0;
            centroid_x <= 0;
            centroid_y <= 0;
            valid <= 0;
        end else if (end_frame) begin
            red_object_valid <= ((scaled_red >= scaled_area) && red_pixel_counter >= PIXEL_THRESHOLD);
            if (red_pixel_counter != 0) begin
                centroid_x <= sum_x / red_pixel_counter;
                centroid_y <= sum_y / red_pixel_counter;
                valid <= 1;
            end else begin
                centroid_x <= 0;
                centroid_y <= 0;
                valid <= 0;
            end
        end else begin
            valid <= 0;
        end
    end

endmodule
