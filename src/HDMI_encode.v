`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/4/2025 6:22:26 PM
// Design Name: 
// Module Name: HDMI_encode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision 0.01 - File Created
// Orginal: George Yu (georgeyhere)
//
// Modifications: fixed minor HDMI protocol issue
// According to HDMI/DVI TMDS spec:
//   - Channel 0: Blue + {VSync, HSync}
//   - Channel 1: Green
//   - Channel 2: Red
// This implementation routes each correctly per the standard. 
// 
//////////////////////////////////////////////////////////////////////////////////


module HDMI_encode(
    input        i_p_clk,
    input        i_resetn,

    // 8-bit RGB in
    input  [7:0] i_red,
    input  [7:0] i_green,
    input  [7:0] i_blue,

    // timing signals
    input        i_vsync,
    input        i_hsync,
    input        i_active_area,     
    
    // 10-bit TMDS-encoded RGB out
    output [9:0] o_tmds_red,
    output [9:0] o_tmds_green,
    output [9:0] o_tmds_blue
    );
    
//
//
//

    // Channel 0 — Blue + Timing
TMDS_encoder2 TMDS_CH0(     
    .clk      (i_p_clk),
    .Reset    (~i_resetn),
    .de       (i_active_area),
    .ctrl     ({i_vsync, i_hsync}),  // only used when DE = 0
    .din      (i_blue),
    .dout     (o_tmds_blue)
);

// Channel 1 — Green
TMDS_encoder2 TMDS_CH1(     
    .clk      (i_p_clk),
    .Reset    (~i_resetn),
    .de       (i_active_area),
    .ctrl     (2'b0),                // not used
    .din      (i_green),
    .dout     (o_tmds_green)
);

// Channel 2 — Red
TMDS_encoder2 TMDS_CH2(     
    .clk      (i_p_clk),
    .Reset    (~i_resetn),
    .de       (i_active_area),
    .ctrl     (2'b0),                // not used
    .din      (i_red),
    .dout     (o_tmds_red)
);
    
endmodule
