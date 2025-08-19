`default_nettype none
//
//

// MODIFICATIONS: Gated writes and reads
module fifo_sync
    #(parameter DATA_WIDTH         = 8,
      parameter ADDR_WIDTH         = 9,
      parameter ALMOSTFULL_OFFSET  = 2,
      parameter ALMOSTEMPTY_OFFSET = 2
      )
    (
    input  wire                   i_clk,
    input  wire                   i_rstn,
                   
    input  wire                   i_wr,
    input  wire [DATA_WIDTH-1:0]  i_data,
                  
    input  wire                   i_rd,
    output reg  [DATA_WIDTH-1:0]  o_data,

    output reg  [ADDR_WIDTH:0]    o_fill,
    
    output wire                   o_full,
    output wire                   o_almostfull,
    output wire                   o_empty,
    output wire                   o_almostempty,
    
    output wire                   o_error
    );

    localparam FIFO_DEPTH = (1<<ADDR_WIDTH);

    reg  [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    wire [DATA_WIDTH-1:0] rdata;
    
    reg  [ADDR_WIDTH-1:0] wptr;             
    reg  [ADDR_WIDTH-1:0] rptr;
    
    // gated enables
    wire wr_ok = i_wr && (o_fill != FIFO_DEPTH);
    wire rd_ok = i_rd && (o_fill != 0);

// distributed ram
    always@(posedge i_clk) begin
        if(wr_ok) begin
            mem[wptr] <= i_data;
        end
    end
    assign rdata = mem[rptr];
    always@(posedge i_clk) begin // output register
        if (rd_ok) begin
            o_data <= rdata;
        end
    end

// write pointer
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            wptr <= 0;
        end
        else if (wr_ok) begin
            wptr <= (i_wr) ? wptr+1 : wptr;
        end
    end

// read pointer
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            rptr <= 0;
        end
        else if (rd_ok) begin
            rptr <= (i_rd) ? rptr+1 : rptr;
        end
    end

// o_fill and status
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            o_fill <= 0;
        end
        else if (rd_ok && !wr_ok) begin
            o_fill <= o_fill - 1'b1;
        end
        else if (!rd_ok && wr_ok) begin
            o_fill <= o_fill + 1'b1;
        end
    end

    assign o_full        = (o_fill == FIFO_DEPTH);
    assign o_almostfull  = (o_fill == FIFO_DEPTH-ALMOSTFULL_OFFSET);
    assign o_empty       = (o_fill == 0);
    assign o_almostempty = (o_fill <= ALMOSTEMPTY_OFFSET);
    assign o_error       = ((o_fill == 0) && (i_rd)) ||
                           ((o_fill == FIFO_DEPTH) && (i_wr));

endmodule // fifo_sync
