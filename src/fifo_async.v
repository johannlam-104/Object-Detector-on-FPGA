
module fifo_async 
    #(parameter DATA_WIDTH         = 2,
      parameter PTR_WIDTH          = 4,
      parameter ALMOSTFULL_OFFSET  = 2,
      parameter ALMOSTEMPTY_OFFSET = 2)
     
    (
    input  wire                  i_wclk,
    input  wire                  i_wrstn,
    input  wire                  i_wr,
    input  wire [DATA_WIDTH-1:0] i_wdata,
    output reg                   o_wfull,
    output reg                   o_walmostfull,
    output reg  [PTR_WIDTH-1:0]  o_wfill,

    input  wire                  i_rclk,
    input  wire                  i_rrstn,
    input  wire                  i_rd,
    output wire [DATA_WIDTH-1:0] o_rdata,
    output reg                   o_rempty,
    output reg                   o_ralmostempty,
    output reg  [PTR_WIDTH-1 :0] o_rfill
    );


    reg  [DATA_WIDTH-1:0] mem [0:((1<<PTR_WIDTH)-1)];
 
    reg  [PTR_WIDTH  :0]  rq1_wptr;
    reg  [PTR_WIDTH  :0]  rq2_wptr;

    wire [PTR_WIDTH-1:0] raddr;

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
    assign o_rdata = mem[raddr];
    always@(posedge i_wclk) begin
        if((i_wr) && (!o_wfull)) mem[waddr] <= i_wdata;
    end

    /*
    always@(posedge i_rclk) begin
        o_rdata <= mem[raddr];
    end
    */

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
    assign rbinnext  = rbin + { {(PTR_WIDTH){1'b0}}, ((i_rd)&&(!o_rempty)) };


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
//
//

//
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
    assign wbinnext = wbin + { {(PTR_WIDTH){1'b0}}, ((i_wr) && (!o_wfull)) };

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