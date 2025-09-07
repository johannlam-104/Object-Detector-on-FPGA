`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/04/2025 09:49:54 AM
// Design Name: 
// Module Name: VGA_top
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


module VGA_top(
    input wire i_p_clk,
    input wire i_rstn,
    
    input  wire [11:0]  i_pixel,
    
    input  wire        i_vsync,
    input  wire        i_hsync,
    input  wire        i_active_area,
    
    output reg [3:0] o_R,
    output reg [3:0] o_G,
    output reg [3:0] o_B,
    
    output reg       o_HS,
    output reg       o_VS
    );
    
    reg [11:0] pixel_d;
    reg        active_d;
    reg        vs_d;
    reg        hs_d;

    always @(posedge i_p_clk) begin
        if (!i_rstn) begin
            pixel_d   <= 12'd0;
            active_d  <= 1'b0;
            o_R <= 4'd0;
            o_G <= 4'd0;
            o_B <= 4'd0;
        end else begin
            // stage 0: register inputs
            pixel_d  <= i_pixel;
            active_d <= i_active_area;
            vs_d     <= i_vsync;
            hs_d     <= i_hsync;

            // stage 1: drive DAC lines, blank when not active
            if (active_d) begin
                o_R <= pixel_d[11:8];
                o_G <= pixel_d[7:4];
                o_B <= pixel_d[3:0];
                o_HS <= hs_d;
                o_VS <= vs_d;
            end else begin
                o_R <= 4'd0;
                o_G <= 4'd0;
                o_B <= 4'd0;
                o_HS <= 0;
                o_VS <= 0;
            end
        end
    end
    
endmodule
