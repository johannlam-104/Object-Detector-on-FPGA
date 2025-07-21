`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
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


module crossHairOverlay#(
    parameter crosshair_size = 8
)
(
    input wire i_clk,
    input wire i_rstn,
    input wire i_data_valid,
    input wire [11:0] i_data,
    input wire [9:0] centroid_x,
    input wire [8:0] centroid_y,
    input wire end_frame,
    
    output reg o_data_valid,
    output reg o_data
    );
    
    wire draw_cross;
    reg [9:0] x_counter;
    reg [8:0] y_counter;
    
assign draw_cross = 
    ( (x_counter >= centroid_x ? (x_counter - centroid_x) : (centroid_x - x_counter)) <= crosshair_size ) &&
    ( (y_counter >= centroid_y ? (y_counter - centroid_y) : (centroid_y - y_counter)) <= crosshair_size );
    
    always @(posedge i_clk) begin
        if (~i_rstn) begin
            o_data <= 12'b0;
            o_data_valid <= 0;
        end 
        else if (i_data_valid)begin
            if(draw_cross) begin
                o_data <= 12'h0F0; // green crosshair
                o_data_valid <= i_data_valid;
            end 
            else begin
                o_data <= i_data;
                o_data_valid <= i_data_valid;
            end
        end
        else begin
            o_data <= 0;
            o_data_valid <= 0;
        end
    end
    
    always@(posedge i_clk)begin
        if(~i_rstn)begin
            x_counter <= 0;
            y_counter <= 0;
        end
        else if (i_data_valid) begin
            if (end_frame)begin
                x_counter <= 0;
                y_counter <= 0;
            end
            x_counter <= (x_counter == 639) ? 0: x_counter + 1'b1;
            y_counter <= (x_counter == 639) ? y_counter + 1'b1 : y_counter;
        end
    end
    
endmodule
