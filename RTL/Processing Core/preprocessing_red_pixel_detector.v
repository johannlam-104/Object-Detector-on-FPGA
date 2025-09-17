`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/06/2025 09:13:42 PM
// Design Name: 
// Module Name: pp_redPixelDetector
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

// 1-cycle latency 
module pp_redPixelDetector(
    input wire i_clk,
    input wire i_rstn,
    
    input wire i_valid,
    input wire [15:0] i_pixel,
    
    output reg  o_pixel_is_red,
    output reg  o_valid
    );
    
    wire [4:0] r = i_pixel[15:11];
    wire [5:0] g = i_pixel[10:5];
    wire [4:0] b = i_pixel[4:0];

    initial o_valid = 0;

    always@(posedge i_clk) begin
        if(!i_rstn) begin
            o_pixel_is_red  <= 0;
            o_valid <= 0;
        end
        else if(i_valid) begin
            o_valid <= 1;
            if ((r >= 5'd27) & (g <= 6'd12) & (b <= 5'd8)) // strict "fire-truck" red threshold
                o_pixel_is_red <= 1'b1;
            else
                o_pixel_is_red <= 0;
        end
        else begin
            o_pixel_is_red  <= 0;
            o_valid <= 0;
        end
    end
    
endmodule
