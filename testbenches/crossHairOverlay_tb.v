`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Johann Lam
// 
// Create Date: 07/26/2025 12:08:13 PM
// Design Name: 
// Module Name: crossHairOverlay_tb
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
//
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// MUST RUN FOR AT LEAST 3,072,000 NANOSECONDS TO CAPTURE FULL FRAME
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module crossHairOverlay_tb;
    reg i_clk = 0;
    reg i_rstn = 0;
    reg i_data_valid = 0;
    reg [11:0] i_data = 0;
    reg [9:0] i_centroid_x = 320;
    reg [8:0] i_centroid_y = 240;
    reg i_end_frame = 0;
    reg i_red_object_valid = 0;

    wire o_data_valid;
    wire [11:0] o_data;

    // Clock generation
    always #5 i_clk = ~i_clk;

    crossHairOverlay #(
        .crosshair_size(1),
        .IMG_WIDTH(640),
        .IMG_HEIGHT(480)
    ) dut (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_data_valid(i_data_valid),
        .i_data(i_data),
        .i_centroid_x(i_centroid_x),
        .i_centroid_y(i_centroid_y),
        .i_end_frame(i_end_frame),
        .i_red_object_valid(i_red_object_valid),
        .o_data_valid(o_data_valid),
        .o_data(o_data)
    );
    
    
    
    integer x, y;
    reg [11:0] test_pixel = 12'h0;
    
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, crossHairOverlay_tb);
        
        // Reset
        #10;
        i_rstn = 1;
        #10;
        
        i_red_object_valid = 1; // Simulate red object detection
    
        // Simulate one frame of pixels
        for (y = 0; y < 480; y = y + 1) begin
            for (x = 0; x < 640; x = x + 1) begin
                test_pixel = test_pixel + 1;
                i_data = test_pixel;
                i_data_valid = 1;
                i_end_frame = (y == 479 && x == 639) ? 1 : 0;
    
                i_centroid_x = 320;
                i_centroid_y = 240;
    
                #10; // One pixel per clock cycle
            end
        end
    
        // Frame ends, FSM should go back to IDLE
        i_data_valid = 0;
        i_end_frame = 0;
        i_red_object_valid = 0;
    
        #50;
        $finish;
    end


endmodule

