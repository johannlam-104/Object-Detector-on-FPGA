`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/12/2025 05:18:40 PM
// Design Name: 
// Module Name: redObjectDetectorTop
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


module preprocessingTop(
    input  wire         i_clk,   // input clock
    input  wire         i_rstn,  // sync active low reset
    input  wire         i_flush,


    // Pixel Capture FIFO interface
    output reg          o_rd,    // read enable
    input  wire [11:0]  i_data,  // input data (RGB444)
    input  wire         i_almostempty, 
 
    // Output FIFO interface
    input  wire         i_rd,    // read enable
    output wire         o_data,  // output data
    output wire [10:0]  o_fill,  //
    output wire         o_almostempty
    );
    
    reg red_pixel;
    reg pp_valid;
    
    
    reg  [11:0] din;
    reg         din_valid, nxt_din_valid;
    reg         nxt_rd;
    reg  [9:0]  nxt_rdCounter, rdCounter;

// red pixel signals
    wire        redpixelfiltering_valid;
    wire        redpixelfiltering_dout;

// Output FIFO
    wire        fifo_wr;
    wire        fifo_wdata;
    wire        fifo_rdata;
    wire        fifo_almostempty;
    wire        fifo_almostfull;
    wire        fifo_empty;

    
    reg STATE, NEXT_STATE;
    localparam STATE_IDLE   = 0,
               STATE_ACTIVE = 1;
    initial STATE = STATE_IDLE;
    
    // FSM next state logic for FIFO reads
//
    always@* begin
        nxt_rd        = 0;
        nxt_din_valid = 0;
        nxt_rdCounter = rdCounter;
        NEXT_STATE    = STATE;

        case(STATE)
            
            STATE_IDLE: begin
                if(!i_almostempty) begin
                    nxt_rd        = 1;
                    nxt_din_valid = 1;
                    NEXT_STATE    = STATE_ACTIVE;
                end
            end

            STATE_ACTIVE: begin
                nxt_rd        = (!i_almostempty);
                nxt_din_valid = (!i_almostempty);
                if(i_almostempty) begin
                    NEXT_STATE = STATE_IDLE;
                end
            end
        endcase
    end

// FSM sync process
//
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            o_rd      <= 0;
            din_valid <= 0;
            rdCounter <= 0;
            STATE     <= STATE_IDLE;
        end    
        else begin    
            o_rd      <= nxt_rd;
            din_valid <= nxt_din_valid;
            rdCounter <= nxt_rdCounter;
            STATE     <= NEXT_STATE;
        end
    end
    
    assign  fifo_wr    = (!fifo_almostfull) ? din_valid : 0;
    assign  fifo_wdata = red_pixel;

    
    pp_redPixelDetector preprocessing_i(
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    
    .i_valid(din_valid),
    .i_pixel(i_data),
    
    .o_pixel_is_red(red_pixel),
    .o_valid(pp_valid)
    );
    
    
   fifo_sync 
    #(.DATA_WIDTH        (1),
      .ADDR_WIDTH        (10),
      .ALMOSTFULL_OFFSET (2),
      .ALMOSTEMPTY_OFFSET(1))
    pp_obuf_i (
    .i_clk         (i_clk              ),
    .i_rstn        (i_rstn&&(~i_flush) ),
             
    .i_wr          (fifo_wr            ),
    .i_data        (fifo_wdata         ),
               
    .i_rd          (i_rd               ),
    .o_data        (o_data             ),
    
    .o_fill        (o_fill             ),

    .o_full        (),   
    .o_almostfull  (fifo_almostfull    ),
    .o_empty       (fifo_empty         ),
    .o_almostempty (o_almostempty      )
    );

    
endmodule
