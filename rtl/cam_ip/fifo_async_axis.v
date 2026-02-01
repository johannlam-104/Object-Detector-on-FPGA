// ==============================================================================
// ******************* OPEN SOURCED, ORIGINAL CREDITS: GEORGE YU ****************
// ------------------------------------------------------------------------------
//                              MODIFICATIONS
// * implemented axi-stream functionality on the read side 
// ==============================================================================
module fifo_async_axis 
    #(parameter TDATA_WIDTH         = 32,
      parameter TUSER_WIDTH         = 1,
      parameter PTR_WIDTH          = 4,
      parameter ALMOSTFULL_OFFSET  = 2,
      parameter ALMOSTEMPTY_OFFSET = 2)
     
    (
    // write side
    input  wire                  i_wclk,
    input  wire                  i_wrstn,
    
    // write side interface (compact axi-stream)
    output wire                             o_sready, // not full flag
    input  wire                             i_wr_valid, 
    input  wire [TDATA_WIDTH+TUSER_WIDTH:0] i_wr_data, // 16 bit pixel data + 16'h0000 + 2 bit meta data
    
    // read side 
    input  wire                   i_rclk,
    input  wire                   i_rrstn,
    
    // read side (real axi-stream interface)
    input  wire                   i_mready, // from VDMA
    output reg                    o_rd_valid,
    output reg  [TDATA_WIDTH-1:0] o_rd_data,
    output reg  [TUSER_WIDTH-1:0] o_tuser,
    output reg                    o_tlast,
    
    // write side combinational flags
    output reg                   o_wfull,
    output reg                   o_walmostfull,
    output reg  [PTR_WIDTH-1:0]  o_wfill,
    
    // read side combinational flags
    output reg                   o_rempty,
    output reg                   o_ralmostempty,
    output reg  [PTR_WIDTH-1 :0] o_rfill
    );

    localparam integer W = TDATA_WIDTH + TUSER_WIDTH + 1;

    reg  [W-1:0] mem [0:((1<<PTR_WIDTH)-1)];
    
    reg  [PTR_WIDTH  :0]  rq1_wptr;
    reg  [PTR_WIDTH  :0]  rq2_wptr;

    wire [PTR_WIDTH-1:0] raddr;
    
    wire [W-1:0] mem_word = mem[raddr];

    wire [TDATA_WIDTH-1:0] tdata_w = mem_word[W-1 : (TUSER_WIDTH+1)];
    wire [TUSER_WIDTH-1:0] tuser_w = mem_word[(TUSER_WIDTH) : 1];
    wire                   tlast_w = mem_word[0];
    
    reg  [PTR_WIDTH  :0] rbin; 
    wire [PTR_WIDTH  :0] rbinnext;
    wire [PTR_WIDTH  :0] rbinnext2;

    reg  [PTR_WIDTH  :0] rptr;
    wire [PTR_WIDTH  :0] rgraynext; 

    wire rempty_val;

    reg  [PTR_WIDTH  :0] wq1_rptr;
    reg  [PTR_WIDTH  :0] wq2_rptr;

    wire [PTR_WIDTH-1:0] waddr;

    reg  [PTR_WIDTH  :0] wbin;
    wire [PTR_WIDTH  :0] wbinnext;

    reg  [PTR_WIDTH  :0] wptr;
    wire [PTR_WIDTH  :0] wgraynext;

    wire wfull_val;

//
// FIFO MEMORY
// synthesized with ram primitives

// write side
    assign o_sready = !o_wfull;
    always@(posedge i_wclk) begin
        if((i_wr_valid) && (!o_wfull)) mem[waddr] <= i_wr_data;
    end

    
// Output register behaves like a 1-deep skid buffer:
// - If output reg is empty, we prefetch from FIFO when not empty.
// - If output reg is full and downstream ready, we consume it and (optionally) prefetch next.

    wire out_fire    = o_rd_valid && i_mready;                // AXIS handshake
    wire out_canload = ~o_rd_valid || out_fire;               // output reg free this cycle
    wire rd_pop      = out_canload && ~o_rempty;              // pop from FIFO into output reg
    
    always @(posedge i_rclk or negedge i_rrstn) begin
        if (!i_rrstn) begin
            o_rd_valid <= 1'b0;
            o_rd_data  <= {TDATA_WIDTH{1'b0}};
            o_tuser    <= {TUSER_WIDTH{1'b0}};
            o_tlast    <= 1'b0;
        end else begin
            if (rd_pop) begin
                // Load next FIFO word into output register
                o_rd_valid <= 1'b1;
                o_rd_data  <= tdata_w;
                o_tuser    <= tuser_w;
                o_tlast    <= tlast_w;
            end 
            else if (out_fire) begin
                // No new word to load, but downstream consumed current beat
                o_rd_valid <= 1'b0;
            end
            // else: hold everything stable (AXI requirement)
        end
    end
    

//
// synchronize write pointer to read clock domain via 2FF
//
    initial {rq1_wptr, rq2_wptr} = 0;
    always@(posedge i_rclk or negedge i_rrstn) begin
        if(!i_rrstn) {rq2_wptr, rq1_wptr} <= 0;
        else         {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};
    end

//
// read pointer and empty generation logic
//
    // MEMORY READ ADDRESS POINTER (binary)
    assign raddr = rbin[PTR_WIDTH-1:0];

    // BINARY COUNTER FOR MEMORY ADDRESSING
    initial rbin = 0;
    always@(posedge i_rclk or negedge i_rrstn) begin
        if(!i_rrstn) rbin <= 0;
        else         rbin <= rbinnext;
    end
    assign rbinnext  = rbin + { {(PTR_WIDTH){1'b0}}, rd_pop };


     // GRAY-CODE READ POINTER
    initial rptr = 0;
    always@(posedge i_rclk or negedge i_rrstn) begin
        if(!i_rrstn) rptr <= 0;
        else         rptr <= rgraynext;
    end
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;

    // EMPTY FLAG LOGIC
    initial o_rempty = 1;
    always@(posedge i_rclk or negedge i_rrstn) begin 
        if(!i_rrstn) o_rempty <= 1;
        else         o_rempty <= rempty_val; 
    end
    assign rempty_val = (rgraynext == rq2_wptr);

    // READ FILL LEVEL
    wire [PTR_WIDTH:0] rdiff;
    wire [PTR_WIDTH:0] rq2_wptr_bin;
    assign rq2_wptr_bin[PTR_WIDTH] = rq2_wptr[PTR_WIDTH];
    for(genvar i=PTR_WIDTH-1; i>=0; i=i-1) begin
        xor(rq2_wptr_bin[i], rq2_wptr[i], rq2_wptr_bin[i+1]);
    end

    assign rdiff = (rbinnext <= rq2_wptr_bin) ? (rq2_wptr_bin - rbinnext) :
                                    ((1<<(PTR_WIDTH+1)) - rbinnext + rq2_wptr_bin); 

    always@(posedge i_rclk or negedge i_rrstn) begin
        if(!i_rrstn) o_rfill <= 0;
        else         o_rfill <= rdiff;
    end

    // ALMOST EMPTY FLAG
    wire almostempty_val;
    assign almostempty_val = (rdiff <= ALMOSTEMPTY_OFFSET);
    always@(posedge i_rclk or negedge i_rrstn) begin
        if(!i_rrstn) o_ralmostempty <= 1;
        else         o_ralmostempty <= almostempty_val;
    end

// ****

// synchronize read pointer to write clock domain
//
    initial {wq1_rptr, wq2_rptr} = 0;
    always@(posedge i_wclk or negedge i_wrstn) begin
        if(!i_wrstn) {wq2_rptr, wq1_rptr} <= 0;
        else         {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};
    end

//
// write pointer and full generation logic
//
    // MEMORY WRITE ADDRESS POINTER (binary)
    assign waddr = wbin[PTR_WIDTH-1:0];

    // BINARY COUNTER FOR MEMORY ADDRESSING
    initial wbin = 0;
    always@(posedge i_wclk or negedge i_wrstn) begin
        if(!i_wrstn) wbin <= 0;
        else         wbin <= wbinnext;
    end
    assign wbinnext = wbin + { {(PTR_WIDTH){1'b0}}, ((i_wr_valid) && (!o_wfull)) };

    // GRAY-CODE WRITE POINTER
    initial wptr = 0;
    always@(posedge i_wclk or negedge i_wrstn) begin
        if(!i_wrstn) wptr <= 0;
        else         wptr <= wgraynext;
    end
    assign wgraynext = (wbinnext >> 1) ^ wbinnext; // 100

    // FULL FLAG LOGIC
    initial o_wfull = 0;
    always@(posedge i_wclk or negedge i_wrstn) begin
        if(!i_wrstn) o_wfull <= 0;
        else         o_wfull <= wfull_val;
    end
    assign wfull_val = (wgraynext == {~wq2_rptr[PTR_WIDTH:PTR_WIDTH-1], 
                                       wq2_rptr[PTR_WIDTH-2:0]});

    // WRITE FILL LEVEL
    wire [PTR_WIDTH:0] wdiff;
    wire [PTR_WIDTH:0] wq2_rptr_bin;
    assign wq2_rptr_bin[PTR_WIDTH] = wq2_rptr[PTR_WIDTH];
    for(genvar i=PTR_WIDTH-1; i>=0; i=i-1) begin
        xor(wq2_rptr_bin[i], wq2_rptr[i], wq2_rptr_bin[i+1]);
    end

    assign wdiff = (wq2_rptr_bin <= wbinnext) ? (wbinnext - wq2_rptr_bin) :
                                    ((1<<(PTR_WIDTH+1)) - wq2_rptr_bin + wbinnext); 

    always@(posedge i_wclk or negedge i_wrstn) begin
        if(!i_wrstn) o_wfill <= 0;
        else         o_wfill <= wdiff;
    end

    // ALMOST FULL FLAG
    wire almostfull_val;
    assign almostfull_val = (o_wfill >= ( ((1<<PTR_WIDTH)-ALMOSTFULL_OFFSET)) ) ||
                            (wgraynext == {~wq2_rptr[PTR_WIDTH:PTR_WIDTH-1], wq2_rptr[PTR_WIDTH-2:0]});
                                                       
    always@(posedge i_wclk or negedge i_wrstn) begin
        if(!i_wrstn) o_walmostfull <= 1;
        else         o_walmostfull <= almostfull_val;
    end

endmodule