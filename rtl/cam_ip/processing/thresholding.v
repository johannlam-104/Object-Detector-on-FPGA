`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// determines if incoming pixel is "red enough"
// accumulates metadata into the same data bus
// input: {RGB444, 20'b0} -> output {RGB444, pixel_is_red, 10'b(x-coor), 9'b(y-coor)}
//////////////////////////////////////////////////////////////////////////////////
// my version

module thresholding(
    input wire          i_clk,
    input wire          i_rstn,
    
    // write side
    input wire          i_tvalid, // per pixel valid
    input wire [31:0]   i_tdata,
    input wire          i_tuser,
    input wire          i_tlast,
    output wire         o_tready, // always high
    
    // read side
    output reg [31:0]   o_tdata, // pixel is red or not o_tdata[19]
    output reg          o_tuser, // sof
    output reg          o_tlast, // eol
    output reg          o_tvalid,
    input wire          i_tready // preprocessing fifo not full
    );
    
    wire [3:0] r = i_tdata[31:28]; 
    wire [3:0] g = i_tdata[27:24];
    wire [3:0] b = i_tdata[23:20];
    
    assign o_tready = i_tready || !o_tvalid;
    
    wire in_xfer  = i_tvalid && o_tready;   // accept new input
    wire out_xfer = o_tvalid && i_tready;   // consumer accepted output
    
    reg  [9:0] x_curr;
    reg  [8:0] y_curr;
    wire [9:0] x = x_curr;
    wire [8:0] y = y_curr;
    
    wire is_red = ((r >= 4'd12) && (g <= 4'd3) && (b <= 4'd3));
    
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            o_tdata     <= 0;
            o_tvalid    <= 0;
            o_tuser     <= 0;
            o_tlast     <= 0;
            
            x_curr      <= 0;
            y_curr      <= 0;
        end
        else begin
            // If we can accept a new beat, load output regs
            if (in_xfer) begin
                o_tvalid <= 1'b1;
                o_tuser  <= i_tuser;
                o_tlast  <= i_tlast;
                o_tdata  <= {r, g, b, is_red, x, y}; // original x, y
                
                x_curr   <= (i_tlast) ? 0 : x_curr + 1;
                y_curr   <= i_tuser ? 0 : (i_tlast ? y_curr + 1 : y_curr);
            end
            else if (out_xfer && !in_xfer) begin
                o_tvalid <= 1'b0;
            end
            // else: hold regs stable while stalled
        end
    end

endmodule

