`timescale 1ns / 1ps

// 1-cycle latency 
module pp_redPixelDetector(
    input wire          i_clk,
    input wire          i_rstn,
    
    // write side
    input wire          i_tvalid, // per pixel valid
    input wire [31:0]   i_tdata,
    input wire          i_tuser,
    input wire          i_tlast,
    output wire         o_tready, // always high
    
    // read side
    output reg          o_tdata, // pixel is red or not
    output reg          o_tuser, // sof
    output reg          o_tlast, // eol
    output reg          o_tvalid,
    input wire          i_tready // preprocessing fifo not full
    );
    
    wire [4:0] r = i_tdata[31:27]; 
    wire [5:0] g = i_tdata[26:21];
    wire [4:0] b = i_tdata[20:16];
    
    assign o_tready = i_tready || !o_tvalid;
    
    wire in_xfer  = i_tvalid && o_tready;   // accept new input
    wire out_xfer = o_tvalid && i_tready;   // consumer accepted output

    
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            o_tdata     <= 0;
            o_tvalid    <= 0;
            o_tuser     <= 0;
            o_tlast     <= 0;
        end
        else begin
            // If we can accept a new beat, load output regs
            if (in_xfer) begin
                o_tvalid <= 1'b1;
                o_tuser  <= i_tuser;
                o_tlast  <= i_tlast;
                o_tdata  <= ((r >= 5'd20) && (g <= 6'd12) && (b <= 5'd10)) ? 1'b1 : 1'b0;
            end
            else if (out_xfer) begin
                o_tvalid <= 1'b0;
            end
            // else: hold regs stable while stalled
        end
    end

endmodule
