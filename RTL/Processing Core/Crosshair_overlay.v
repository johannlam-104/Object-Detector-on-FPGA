`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Johann Lam
// 
// Create Date: 07/11/2025 11:28:19 PM
// Design Name: 
// Module Name: crossHairOverlay
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

// --------------------------------------------------------------------------
// This module is an fsm that essentially latches on whether the red object valid
// is asserted, so if the upstream centroid calculation module determines the 
// red object is valid, it will display the regular pixel data but change 
// the centroid pixels to green, if the centroid module doesnt detect a valid object
// the entire frame is fed unchanged 
// NOTE: DUE TO THE NATURE OF CENTROID CALC, THE CROSSHAIR WILL LAG BY 1 FULL FRAME!!
//---------------------------------------------------------------------------
//
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------

// 1-cycle latency
module crossHairOverlay #(
    parameter CROSSHAIR_SIZE = 3, // thickness = CROSSHAIR_SIZE * 2 + 1
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    input  wire        i_data_valid,
    input  wire [15:0] i_data,

    input  wire [9:0]  i_centroid_x,
    input  wire [8:0]  i_centroid_y,
    input  wire        i_end_frame,        // 1-cycle strobe at end of frame
    input  wire        i_red_object_valid, // strobe-valid at end of frame

    output reg         o_data_valid,
    output reg  [15:0] o_data
);

    // =========================================================================
    // Latch the centroid & "frame had red" on end-of-frame for use NEXT frame
    // =========================================================================
    
    reg        next_frame_has_red;
    // these saved centroids are first captured
    reg [9:0]  saved_centroid_x;
    reg [8:0]  saved_centroid_y;
    
    
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            next_frame_has_red <= 1'b0;
            saved_centroid_x   <= 10'd0;
            saved_centroid_y   <= 9'd0;
        end 
        else begin
            if(i_end_frame)begin
                next_frame_has_red <= i_red_object_valid;
                saved_centroid_x   <= i_centroid_x;
                saved_centroid_y   <= i_centroid_y;
            end
        end
    end

    // =========================================================================
    // FSM + raster counters
    // =========================================================================
    localparam STATE_IDLE   = 2'b00;
    localparam STATE_RED    = 2'b01;
    localparam STATE_NO_RED = 2'b10;

    reg [1:0] STATE, NEXT_STATE;

    reg [9:0] x_counter, next_x_counter;
    reg [8:0] y_counter, next_y_counter;

    // Latched copy used while drawing (fixed for the whole frame) 
    // Done in the FSM
    reg [9:0] latched_centroid_x, next_latched_centroid_x;
    reg [8:0] latched_centroid_y, next_latched_centroid_y;

    // Crosshair condition
    wire [9:0] dx = (x_counter > latched_centroid_x) ? (x_counter - latched_centroid_x)
                                                     : (latched_centroid_x - x_counter);
    wire [8:0] dy = (y_counter > latched_centroid_y) ? (y_counter - latched_centroid_y)
                                                     : (latched_centroid_y - y_counter);

    wire draw_crosshair = (dx <= CROSSHAIR_SIZE) || (dy <= CROSSHAIR_SIZE);

    // Next-state / comb
    reg [15:0] next_data;
    reg        next_o_data_valid;
    
    

    always @* begin
        NEXT_STATE              = STATE;
        next_data               = i_data;
        next_o_data_valid       = 1'b0;

        next_x_counter          = x_counter;
        next_y_counter          = y_counter;

        next_latched_centroid_x = latched_centroid_x;
        next_latched_centroid_y = latched_centroid_y;

        case (STATE)
            // --------------------------------------------------------------
            // Wait for first pixel of a frame; decide mode for the whole frame
            // based on the *latched* "next_frame_has_red".
            // --------------------------------------------------------------
            STATE_IDLE: begin
                if (i_data_valid) begin
                    next_o_data_valid = 1'b1;
                    if (next_frame_has_red) begin
                        NEXT_STATE              = STATE_RED;
                        next_latched_centroid_x = saved_centroid_x;
                        next_latched_centroid_y = saved_centroid_y;
                        next_data               = draw_crosshair ? 16'h07E0 : i_data;
                    end 
                    else begin
                        NEXT_STATE              = STATE_NO_RED;
                        next_latched_centroid_x = 10'd0;
                        next_latched_centroid_y = 9'd0;
                        next_data               = i_data;
                    end
                end
            end

            // --------------------------------------------------------------
            // Drawing with crosshair overlay 
            // --------------------------------------------------------------
            STATE_RED: begin
                if (i_end_frame) begin // original end_frame_arm
                    NEXT_STATE              = STATE_IDLE;
                    next_x_counter          = 10'd0;
                    next_y_counter          = 10'd0;
                    next_o_data_valid       = 1'b1;
                    next_latched_centroid_x = 10'd0;
                    next_latched_centroid_y = 9'd0;
                end
                else if (i_data_valid) begin
                    next_o_data_valid = 1'b1;
                    next_data         = draw_crosshair ? 16'h07E0 : i_data;
                    next_x_counter    = (x_counter == IMG_WIDTH-1) ? 10'd0 : (x_counter + 1'b1);
                    next_y_counter    = (x_counter == IMG_WIDTH-1) ? (y_counter + 1'b1) : y_counter;
                end
            end


            // --------------------------------------------------------------
            // Pass-through pixels (no red object last frame)
            // --------------------------------------------------------------
            STATE_NO_RED: begin
                if (i_end_frame) begin  // original end_frame_arm
                    NEXT_STATE              = STATE_IDLE;
                    next_x_counter          = 10'd0;
                    next_y_counter          = 9'd0;
                    next_o_data_valid       = 1'b1;
                    next_latched_centroid_x = 10'd0;
                    next_latched_centroid_y = 9'd0;
                end 
                else if (i_data_valid) begin
                    next_o_data_valid       = 1'b1;
                    next_data               = i_data;
                    next_x_counter          = (x_counter == IMG_WIDTH-1) ? 10'd0 : (x_counter + 1'b1);
                    next_y_counter          = (x_counter == IMG_WIDTH-1) ? (y_counter + 1'b1) : y_counter;
                end
            end

            default: begin
                NEXT_STATE              = STATE_IDLE;
                next_x_counter          = 10'd0;
                next_y_counter          = 9'd0;
                next_o_data_valid       = 1'b0;
                next_latched_centroid_x = 10'd0;
                next_latched_centroid_y = 9'd0;
            end
        endcase
    end

    // registers
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            STATE                <= STATE_IDLE;
            x_counter            <= 10'd0;
            y_counter            <= 9'd0;
            o_data               <= 16'd0;
            o_data_valid         <= 1'b0;
            latched_centroid_x   <= 10'd0;
            latched_centroid_y   <= 9'd0;
        end 
        else begin
            STATE                <= NEXT_STATE;
            x_counter            <= next_x_counter;
            y_counter            <= next_y_counter;
            o_data               <= next_data;
            o_data_valid         <= next_o_data_valid;
            latched_centroid_x   <= next_latched_centroid_x;
            latched_centroid_y   <= next_latched_centroid_y;
        end
    end

endmodule
