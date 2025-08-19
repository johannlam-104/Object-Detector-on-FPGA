`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/06/2025 09:25:52 PM
// Design Name: 
// Module Name: redPixelFilter
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

// 2-cycle latency
module ps_redPixelFilter(
    input wire i_clk,
    input wire i_rstn,
    
    input wire [2:0] i_r0_data,
    input wire [2:0] i_r1_data, 
    input wire [2:0] i_r2_data,
    input wire       i_valid,

    // output interface
    output reg         o_red_pixel_valid,    
    output reg         o_valid    // valid flag
    );
    
    reg [8:0] kernel;
    
    wire [3:0] sum;
    assign sum  = kernel[0] + kernel[1] + kernel[2] + kernel[3] + kernel[5] + kernel[6] + kernel[7] + kernel[8];
    
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            kernel            <= 9'b0;
            o_red_pixel_valid <= 1'b0;
            o_valid           <= 1'b0;
        end 
        else begin
            // stage 1: capture neighborhood regardless of i_valid
            kernel[0] <= i_r0_data[0];
            kernel[1] <= i_r0_data[1];
            kernel[2] <= i_r0_data[2];
            kernel[3] <= i_r1_data[0];
            kernel[4] <= i_r1_data[1];
            kernel[5] <= i_r1_data[2];
            kernel[6] <= i_r2_data[0];
            kernel[7] <= i_r2_data[1];
            kernel[8] <= i_r2_data[2];

            // stage 2: produce result only when upstream says window is valid
            if (i_valid) begin
                o_valid <= 1'b1;
                // require center pixel set and >=5 neighbors (excluding center)
                o_red_pixel_valid <= (kernel[4] && (sum >= 4'd5));
            end 
            else begin
                o_valid           <= 1'b0;
                o_red_pixel_valid <= 1'b0;
            end
        end
    end    
endmodule
