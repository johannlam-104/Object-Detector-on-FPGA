`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Johann Lam
// 
// Create Date: 08/23/2025 11:33:00 PM
// Design Name: 
// Module Name: RGB444_to_RGB888
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

// 1 cycle latency
// prepares data for tmds encoding
module RGB444_to_RGB888#(
    parameter HDMI = 0 // 0 = VGA, 1 = HDMI
)(
    input  wire        i_p_clk,
    input  wire        i_rstn,

    input  wire [11:0] i_data,   // {R[11:8], G[7:4], B[3:0]}
    input  wire        i_valid,

    output reg  [7:0]  o_r_data,
    output reg  [7:0]  o_g_data,
    output reg  [7:0]  o_b_data,
    output reg         o_valid
);

    // pipeline stage 0: capture 4-bit components
    reg [3:0] r4, g4, b4;
    reg       valid_d;

    // expand 4->8 (combinational from stage-0 regs)
    wire [7:0] r8 = {r4,4'b0} + r4;  
    wire [7:0] g8 = {g4,4'b0} + g4;  
    wire [7:0] b8 = {b4,4'b0} + b4; 

    always @(posedge i_p_clk) begin
        if (!i_rstn) begin
            r4      <= 4'd0;
            g4      <= 4'd0;
            b4      <= 4'd0;
            valid_d <= 1'b0;

            o_r_data <= 8'd0;
            o_g_data <= 8'd0;
            o_b_data <= 8'd0;
            o_valid  <= 1'b0;
        end 
        else begin
            // stage 0
            if (i_valid) begin
                r4 <= i_data[11:8];
                g4 <= i_data[7:4];
                b4 <= i_data[3:0];
            end
            valid_d <= i_valid;

            // stage 1 (registered outputs; 1-cycle latency)
            o_valid  <= valid_d;
            if (valid_d) begin
                o_r_data <= r8;
                o_g_data <= g8;
                o_b_data <= b8;
            end
            else begin
                o_r_data <= 8'd0;
                o_g_data <= 8'd0;
                o_b_data <= 8'd0;
            end
        end
    end

endmodule

