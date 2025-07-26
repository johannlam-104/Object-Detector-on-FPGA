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
//---------------------------------------------------------------------------

module crossHairOverlay#(
    parameter crosshair_size = 8,
    parameter IMG_WIDTH = 640,
    parameter IMG_HEIGHT = 480
)
(
    input wire i_clk,
    input wire i_rstn,
    
    input wire i_data_valid,
    input wire [11:0] i_data,
    
    input wire [9:0] i_centroid_x,
    input wire [8:0] i_centroid_y,
    input wire i_end_frame,
    input wire i_red_object_valid,
    
    output reg o_data_valid,
    output reg [11:0] o_data
    );
    
    // state encoding
    reg [1:0] STATE, NEXT_STATE; 
    localparam STATE_IDLE =  2'b00,
              STATE_RED =    2'b01,
              STATE_NO_RED = 2'b10;
    
    wire draw_box;
    reg [9:0] x_counter, next_x_counter;
    reg [8:0] y_counter, next_y_counter;
    
    reg [11:0] next_data;
    reg next_o_data_valid;
    
    assign draw_box = 
    ( (x_counter >= i_centroid_x ? (x_counter - i_centroid_x) : (i_centroid_x - x_counter)) <= crosshair_size ) ||
    ( (y_counter >= i_centroid_y ? (y_counter - i_centroid_y) : (i_centroid_y - y_counter)) <= crosshair_size );
    
    
    always@*begin
        next_data = i_data;
        NEXT_STATE = STATE;
        next_x_counter    = x_counter;
        next_y_counter    = y_counter;
        next_o_data_valid = 0;
        case(STATE) 
        
            STATE_IDLE: begin
                if(i_red_object_valid) begin
                    NEXT_STATE = STATE_RED;
                end
                else begin
                    NEXT_STATE = STATE_NO_RED;
                end
                next_x_counter = 0;
                next_y_counter = 0;
            end
            
            STATE_RED: begin
                if(i_end_frame) begin
                    NEXT_STATE = STATE_IDLE;
                    next_x_counter = 0;
                    next_y_counter = 0;
                end
                else if(i_data_valid) begin
                    next_data = draw_box ? 12'h0F0 : i_data;
                    next_x_counter = (x_counter == IMG_WIDTH - 1) ? 0 : x_counter + 1;
                    next_y_counter = (x_counter == IMG_WIDTH - 1) ? y_counter + 1 : y_counter;
                    next_o_data_valid = 1'b1;
                end
            end

            
            STATE_NO_RED: begin
                if(i_end_frame) begin
                    NEXT_STATE = STATE_IDLE;
                    next_x_counter = 0;
                    next_y_counter = 0;
                end
                else if(i_data_valid) begin
                    next_data = i_data;
                    next_x_counter = (x_counter == IMG_WIDTH - 1) ? 0 : x_counter + 1;
                    next_y_counter = (x_counter == IMG_WIDTH - 1) ? y_counter + 1 : y_counter;
                    next_o_data_valid = 1'b1;
                end
            end
            
            default: begin
                NEXT_STATE = STATE_IDLE;
                next_x_counter = 0;
                next_y_counter = 0;
                next_o_data_valid = 0;
            end
        endcase
    end
    
    always@(posedge i_clk)begin
        if (~i_rstn)begin
            STATE <= STATE_IDLE;
            x_counter <= 0;
            y_counter <= 0;
            o_data <= 0;
            o_data_valid <= 0;
        end
        else begin
            STATE <= NEXT_STATE;
            x_counter <= next_x_counter;
            y_counter <= next_y_counter;
            o_data <= next_data;
            o_data_valid <= next_o_data_valid;
            
        end
    end
endmodule
