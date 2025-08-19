`timescale 1ns / 1ps
// module: ps_linebuffer.v
//
// This is pretty much just a FIFO that outputs three
// words per read. 
//
// Should be synthesized as distributed ram w/ an output
// buffer for better performance -> 1 cycle read latency
//
// MODIFICATIONS: Added clamped edges, edited the kernel control so that 
// this modules deals with vertical edges instead

module ps_linebuffer
    #(
    parameter LINE_LENGTH = 640,
    parameter DATA_WIDTH  = 1,
    parameter CLAMP_EDGES = 1  // 1 = clamp, 0 = wrap
    ) 
    (
    input  wire                    i_clk,
    input  wire                    i_rstn,
            
    // Write Interface            
    input  wire                    i_wr,
    input  wire [DATA_WIDTH-1:0]   i_wdata,
    
    // Read Interface
    input  wire                    i_rd,
    output reg  [3*DATA_WIDTH-1:0] o_rdata
    );

// 
    reg [DATA_WIDTH-1:0] mem [0:LINE_LENGTH-1];
    reg [$clog2(LINE_LENGTH)-1:0] wptr, rptr;

    // Choose neighbor indices based on mode
    wire [$clog2(LINE_LENGTH)-1:0] prev_idx =
        CLAMP_EDGES
        ? (rptr == 0 ? 0 : rptr - 1) // clamp
        : (rptr == 0 ? LINE_LENGTH-1 : rptr - 1); // wrap around 

    wire [$clog2(LINE_LENGTH)-1:0] next_idx =
        CLAMP_EDGES
        ? (rptr == LINE_LENGTH-1 ? LINE_LENGTH-1 : rptr + 1) // clamp
        : (rptr == LINE_LENGTH-1 ? 0 : rptr + 1); // wrap around

    // Async read: three taps
    wire [3*DATA_WIDTH-1:0] rdata = {mem[prev_idx],mem[rptr],mem[next_idx]};

    // Write port
    always @(posedge i_clk) begin 
        if (i_wr) begin
            mem[wptr] <= i_wdata;
        end
    end

    // Registered output (RD_LAT = 1)
    always @(posedge i_clk) begin
        o_rdata <= rdata;
    end

    // Pointers
    always @(posedge i_clk) begin
        if (!i_rstn) 
            wptr <= 0;
        else if (i_wr) 
            wptr <= (wptr == LINE_LENGTH-1) ? 0 : wptr + 1;
    end

    always @(posedge i_clk) begin
        if (!i_rstn) 
            rptr <= 0;
        else if (i_rd) 
            rptr <= (rptr == LINE_LENGTH-1) ? 0 : rptr + 1;
    end
endmodule
