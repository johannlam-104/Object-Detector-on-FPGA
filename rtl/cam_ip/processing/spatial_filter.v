// 
// This module ignores the tuser and tlast metadata and does computation purely
// based on color data.
// unpacks metadata into a full axi-stream for the centroid calc
// data comes in {tdata_prev_indx, tuser_prev_indx, tlast_prev_indx,...
//                tdata_curr_indx, tuser_curr_indx, tlast_curr_indx,...
//                tdata_next_indx, tuser_next_indx, tlast_next_indx} (per line)
// 3 lines of this comes in simultaniously
// uses bit slicing to access only the data portion
// overwrites the previous is_red value in preperation for centroid calc

module ps_redPixelFilter (
    input  wire             i_clk,
    input  wire             i_rstn,

    // 3x3 window rows, each row = {L[33:0], C[33:0], R[33:0]}
    input  wire [101:0]       i_r0_data, // 34 x 3
    input  wire [101:0]       i_r1_data,
    input  wire [101:0]       i_r2_data,

    // input stream valid/ready for the window update
    input  wire             i_tvalid,
    output wire             o_tready,

    // output AXIS (mask stream)
    output reg  [31:0]      o_tdata,   // original data bus (1-bit)
    output reg              o_tuser,   // SOF of center pixel
    output reg              o_tlast,   // EOL of center pixel
    output reg              o_tvalid,
    input  wire             i_tready
);

    // 1-deep reg-slice style
    assign o_tready = i_tready || !o_tvalid;
    wire xfer_in  = i_tvalid && o_tready;
    wire xfer_out = o_tvalid && i_tready;

    // unpack
    wire [33:0] c00 = i_r0_data[101:78], c01 = i_r0_data[77:34], c02 = i_r0_data[33:0];
    wire [33:0] c10 = i_r1_data[101:78], c11 = i_r1_data[77:34], c12 = i_r1_data[33:0];
    wire [33:0] c20 = i_r2_data[101:78], c21 = i_r2_data[77:34], c22 = i_r2_data[33:0];

    wire curr_tuser = c11[1]; // last 2 bits of the data bus
    wire curr_tlast = c11[0];
    
    wire [11:0] curr_rgb = c11[33:22]; // top 12 msbs
    wire [18:0] curr_coordinate = c11[20:2]; // x and y coordinates

    wire k00=c00[21], k01=c01[21], k02=c02[21]; // 22nd index says if this pixel is red enough
    wire k10=c10[21], k11=c11[21], k12=c12[21];
    wire k20=c20[21], k21=c21[21], k22=c22[21];

    wire [3:0] sum = k00 + k01 + k02 +
                     k10 +       k12 +
                     k20 + k21 + k22;

    wire mask_now = (k11 && (sum >= 4'd5)); // overwrite index 21 

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_tvalid <= 1'b0;
            o_tdata  <= 0;
            o_tuser  <= 1'b0;
            o_tlast  <= 1'b0;
        end else begin
            if (xfer_in) begin
                o_tvalid <= 1'b1;
                o_tdata  <= {curr_rgb, mask_now, curr_coordinate};
                o_tuser  <= curr_tuser;
                o_tlast  <= curr_tlast;
            end 
            else if (xfer_out && !xfer_in) begin
                o_tvalid <= 1'b0;
            end
            // else: hold stable while stalled
        end
    end

endmodule
