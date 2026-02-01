`timescale 1ns / 1ps
// packs axi-stream data & metadata into 1 bus
module axis_pack
    #(parameter TDATA_WIDTH        = 32,
      parameter TUSER_WIDTH        = 1
      )
    (
        input  wire                    i_clk,
        input  wire                    i_rstn,
        
        // write side  
        input  wire                    i_tvalid,
        output wire                    o_tready, // can accept data (always high)            
        input  wire [TDATA_WIDTH-1:0]  i_tdata,
        input  wire [TUSER_WIDTH-1:0]  i_tuser, // start of frame
        input  wire                    i_tlast, // end of line
        
        // read side   
        output reg                     o_tvalid,           
        input  wire                    i_tready, // can output (from consumer/kernel)
        output reg  [TDATA_WIDTH+1:0]  o_tpacked
        
    );
        assign o_tready = i_tready || !o_tvalid;
        
        wire wr_valid = i_tvalid && o_tready;
        wire rd_valid = o_tvalid && i_tready;
        
        wire [TDATA_WIDTH+1:0] packed;
        
        assign packed = {i_tdata, i_tuser, i_tlast};
        
        always@(posedge i_clk) begin
            if (!i_rstn) begin
                o_tvalid        <= 0;
                o_tpacked       <= 0;
            end
            else begin
                if (wr_valid) begin
                    o_tvalid        <= i_tvalid;
                    o_tpacked       <= packed;
                end
                else if (rd_valid) begin
                    o_tvalid <= 1'b0;
                end
                // else hold
            end
        end
            
            
endmodule
