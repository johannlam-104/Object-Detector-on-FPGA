`timescale 1ns / 1ps
// module: ps_kernel_control
//
// 4 line buffers. Reads 3 rows per column (2 at top/bottom due to padding).
// Uses a global fill counter that matches actual reads per cycle.
//
// Default DATA_WIDTH=1 for 1-bit pixels.
//
module ps_kernel_control
#(
    parameter LINE_LENGTH = 640,
    parameter LINE_COUNT  = 480,
    parameter DATA_WIDTH  = 1,
    parameter CLAMP_EDGES = 1 //1 = clamp, 0 = wrap
)
(
    input  wire                      i_clk,
    input  wire                      i_rstn,  // sync active-low

    // Input stream
    input  wire [DATA_WIDTH-1:0]     i_data,
    input  wire                      i_valid,
    output reg                       o_req,   // request more input when high

    // 3× window outputs (top/mid/bottom rows for current column)
    output reg  [(3*DATA_WIDTH-1):0] o_r0_data,
    output reg  [(3*DATA_WIDTH-1):0] o_r1_data,
    output reg  [(3*DATA_WIDTH-1):0] o_r2_data,
    output reg                       o_valid
);

    // Next-state
    reg         nxt_req;
    reg         nxt_o_valid;

    // Line buffer enables
    reg  [3:0]  lineBuffer_wr;
    reg  [3:0]  lineBuffer_rd;

    // Line buffer read buses (3*DATA_WIDTH each)
    wire [(3*DATA_WIDTH-1):0] lB0_rdata, lB1_rdata, lB2_rdata, lB3_rdata;

    // Windowed/padded versions per row
    reg  [(3*DATA_WIDTH-1):0] lineBuffer0_rdata;
    reg  [(3*DATA_WIDTH-1):0] lineBuffer1_rdata;
    reg  [(3*DATA_WIDTH-1):0] lineBuffer2_rdata;
    reg  [(3*DATA_WIDTH-1):0] lineBuffer3_rdata;

    // Write-side trackers
    reg  [$clog2(LINE_LENGTH):0]  w_pixelCounter;
    reg  [1:0]                    w_lineBuffer_sel;

    // Global fill (sum across all 4 buffers)
    localparam integer FILL_MAX = 4*LINE_LENGTH;
    reg  [$clog2(FILL_MAX+1)-1:0] r_fill;

    // Read-side trackers
    reg  [$clog2(LINE_LENGTH):0]  r_pixelCounter, nxt_r_pixelCounter;  // columns within a line
    reg  [$clog2(LINE_COUNT):0]   r_lineCounter,  nxt_r_lineCounter;   // which image row
    reg                           r_lineBuffer_rd_en, nxt_r_lineBuffer_rd_en;
    reg  [1:0]                    r_lineBuffer_sel,    nxt_r_lineBuffer_sel;

    // FSM
    reg [1:0]   RSTATE, NEXT_RSTATE;
    localparam  RSTATE_IDLE     = 0,
                RSTATE_PREFETCH = 1,
                RSTATE_ACTIVE   = 2;

    // -------------------------
    // WRITE LOGIC
    // -------------------------
    // Gate writes by o_req 
    wire accept_write = o_req && i_valid;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            w_pixelCounter <= 0;
        end
        else if (accept_write) begin
            w_pixelCounter <= (w_pixelCounter == LINE_LENGTH-1) ? 0 : (w_pixelCounter + 1'b1);
        end
    end

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            w_lineBuffer_sel <= 2'd0;
        end
        else if ((w_pixelCounter == LINE_LENGTH-1) && accept_write) begin
            w_lineBuffer_sel <= (w_lineBuffer_sel == 2'd3) ? 2'd0 : (w_lineBuffer_sel + 2'd1);
        end
    end

    always @* begin
        lineBuffer_wr = 4'b0000;
        lineBuffer_wr[w_lineBuffer_sel] = accept_write;
    end

    // -------------------------
    // FILL ACCOUNTING
    // -------------------------
    // Popcount of reads (formed after READ SELECT)
    wire [1:0] rd_cnt = lineBuffer_rd[0] + lineBuffer_rd[1]
                      + lineBuffer_rd[2] + lineBuffer_rd[3];

    // One write per cycle max
    wire [1:0] wr_cnt = accept_write ? 2'd1 : 2'd0;

    always @(posedge i_clk) begin
        if (!i_rstn) r_fill <= 0;
        else         r_fill <= r_fill + wr_cnt - rd_cnt;
    end

    // -------------------------
    // READ CONTROL FSM
    // -------------------------
    always @* begin
        nxt_req                 = o_req;
        nxt_o_valid             = r_lineBuffer_rd_en;
        nxt_r_lineBuffer_rd_en  = 1'b0;
        nxt_r_pixelCounter      = r_pixelCounter;
        nxt_r_lineCounter       = r_lineCounter;
        nxt_r_lineBuffer_sel    = r_lineBuffer_sel;
        NEXT_RSTATE             = RSTATE;

        case (RSTATE)
            RSTATE_IDLE: begin
                nxt_r_pixelCounter = 0;
                if (r_fill >= (3*LINE_LENGTH)) begin
                    nxt_req                 = 1'b0;
                    nxt_r_lineBuffer_rd_en  = 1'b1;
                    NEXT_RSTATE             = RSTATE_PREFETCH;
                end 
                else begin
                    nxt_req                 = 1'b1;
                    nxt_r_lineBuffer_rd_en  = 1'b0;
                end
            end

            // account for 1 cycle of read latency
            RSTATE_PREFETCH: begin
                nxt_r_lineBuffer_rd_en = 1'b1;
                NEXT_RSTATE            = RSTATE_ACTIVE;
            end

            RSTATE_ACTIVE: begin
                nxt_r_pixelCounter = r_pixelCounter + 1'b1;
                if (r_pixelCounter >= LINE_LENGTH-2) begin
                    nxt_req                 = 1'b1;
                    nxt_r_lineBuffer_rd_en  = 1'b0;
                    nxt_r_lineCounter       = (r_lineCounter == LINE_COUNT-1) ? 0 : (r_lineCounter + 1'b1);
                    nxt_r_lineBuffer_sel    = (r_lineBuffer_sel == 2'd3) ? 2'd0 : (r_lineBuffer_sel + 2'd1);
                    NEXT_RSTATE             = RSTATE_IDLE;
                end 
                else begin
                    nxt_req                 = 1'b0;
                    nxt_r_lineBuffer_rd_en  = 1'b1;
                end
            end
        endcase
    end

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_req              <= 1'b0;
            o_valid            <= 1'b0;
            r_lineBuffer_rd_en <= 1'b0;
            r_pixelCounter     <= 0;
            r_lineCounter      <= 0;
            r_lineBuffer_sel   <= 2'd0;
            RSTATE             <= RSTATE_IDLE;
        end 
        else begin
            o_req              <= nxt_req;
            o_valid            <= nxt_o_valid;
            r_lineBuffer_rd_en <= nxt_r_lineBuffer_rd_en;
            r_pixelCounter     <= nxt_r_pixelCounter;
            r_lineCounter      <= nxt_r_lineCounter;
            r_lineBuffer_sel   <= nxt_r_lineBuffer_sel;
            RSTATE             <= NEXT_RSTATE;
        end
    end

    // -------------------------
    // READ SELECT + OUTPUT WINDOWS
    // -------------------------
    always @* begin
        lineBuffer_rd = {4{r_lineBuffer_rd_en}};
        o_r0_data     = 0;
        o_r1_data     = 0;
        o_r2_data     = 0;

        // First image row (top padding → 2 reads)
        if (r_lineCounter == 0) begin
            lineBuffer_rd[2] = 1'b0;
            lineBuffer_rd[3] = 1'b0;
            o_r0_data        = lineBuffer0_rdata; // top padded with itself
            o_r1_data        = lineBuffer0_rdata; // middle = first row
            o_r2_data        = lineBuffer1_rdata; // bottom = second row
        end
        // Last image row (bottom padding → 2 reads)
        else if (r_lineCounter == LINE_COUNT - 1) begin
            case (r_lineBuffer_sel)
                2'd0: begin
                    lineBuffer_rd[2] = 1'b0; 
                    lineBuffer_rd[1] = 1'b0;
                    o_r0_data = lineBuffer3_rdata;
                    o_r1_data = lineBuffer0_rdata;
                    o_r2_data = lineBuffer0_rdata; // padded
                end
                2'd1: begin
                    lineBuffer_rd[3] = 1'b0; 
                    lineBuffer_rd[2] = 1'b0;
                    o_r0_data = lineBuffer0_rdata;
                    o_r1_data = lineBuffer1_rdata;
                    o_r2_data = lineBuffer1_rdata; // padded
                end
                2'd2: begin
                    lineBuffer_rd[0] = 1'b0; 
                    lineBuffer_rd[3] = 1'b0;
                    o_r0_data = lineBuffer1_rdata;
                    o_r1_data = lineBuffer2_rdata;
                    o_r2_data = lineBuffer2_rdata; // padded
                end
                2'd3: begin
                    lineBuffer_rd[1] = 1'b0; 
                    lineBuffer_rd[0] = 1'b0;
                    o_r0_data = lineBuffer2_rdata;
                    o_r1_data = lineBuffer3_rdata;
                    o_r2_data = lineBuffer3_rdata; // padded
                end
            endcase
        end
        // Middle rows (3 reads)
        else begin
            case (r_lineBuffer_sel)
                2'd0: begin
                    lineBuffer_rd[2] = 1'b0;
                    o_r0_data        = lineBuffer3_rdata;
                    o_r1_data        = lineBuffer0_rdata;
                    o_r2_data        = lineBuffer1_rdata;
                end
                2'd1: begin
                    lineBuffer_rd[3] = 1'b0;
                    o_r0_data        = lineBuffer0_rdata;
                    o_r1_data        = lineBuffer1_rdata;
                    o_r2_data        = lineBuffer2_rdata;
                end
                2'd2: begin
                    lineBuffer_rd[0] = 1'b0;
                    o_r0_data        = lineBuffer1_rdata;
                    o_r1_data        = lineBuffer2_rdata;
                    o_r2_data        = lineBuffer3_rdata;
                end
                2'd3: begin
                    lineBuffer_rd[1] = 1'b0;
                    o_r0_data        = lineBuffer2_rdata;
                    o_r1_data        = lineBuffer3_rdata;
                    o_r2_data        = lineBuffer0_rdata;
                end
            endcase
        end
    end

    localparam WORD3_INDEX = 2*DATA_WIDTH;

    // output regular data, linebuffer module deals with padding along vertical edges
    always @* begin
        lineBuffer0_rdata = lB0_rdata;
        lineBuffer1_rdata = lB1_rdata;
        lineBuffer2_rdata = lB2_rdata;
        lineBuffer3_rdata = lB3_rdata;
    end

    // -------------------------
    // LINE BUFFER INSTANCES
    // -------------------------
    ps_linebuffer #(
        .LINE_LENGTH(LINE_LENGTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CLAMP_EDGES(CLAMP_EDGES)
    ) LINEBUF0_i (
        .i_clk(i_clk), 
        .i_rstn(i_rstn),
        
        .i_wr(lineBuffer_wr[0]), 
        .i_wdata(i_data),
        
        .i_rd(lineBuffer_rd[0]), 
        .o_rdata(lB0_rdata)
    );
    
    ps_linebuffer #(
        .LINE_LENGTH(LINE_LENGTH), 
        .DATA_WIDTH(DATA_WIDTH),
        .CLAMP_EDGES(CLAMP_EDGES)
    ) LINEBUF1_i (
        .i_clk(i_clk), 
        .i_rstn(i_rstn),
        
        .i_wr(lineBuffer_wr[1]), 
        .i_wdata(i_data),
        
        .i_rd(lineBuffer_rd[1]), 
        .o_rdata(lB1_rdata)
    );
    ps_linebuffer #(
        .LINE_LENGTH(LINE_LENGTH), 
        .DATA_WIDTH(DATA_WIDTH),
        .CLAMP_EDGES(CLAMP_EDGES)
    ) LINEBUF2_i (
        .i_clk(i_clk), 
        .i_rstn(i_rstn),
        
        .i_wr(lineBuffer_wr[2]), 
        .i_wdata(i_data),
        
        .i_rd(lineBuffer_rd[2]), 
        .o_rdata(lB2_rdata)
    );
    ps_linebuffer #(
        .LINE_LENGTH(LINE_LENGTH), 
        .DATA_WIDTH(DATA_WIDTH),
        .CLAMP_EDGES(CLAMP_EDGES)
    ) LINEBUF3_i (
        .i_clk(i_clk), 
        .i_rstn(i_rstn),
        
        .i_wr(lineBuffer_wr[3]), 
        .i_wdata(i_data),
        
        .i_rd(lineBuffer_rd[3]), 
        .o_rdata(lB3_rdata)
    );

endmodule
