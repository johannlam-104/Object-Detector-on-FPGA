/*
`default_nettype none
// MODIFICATIONS: 
// * Gated writes and reads
// * implemented axi-stream I/O
`default_nettype none

module fifo_sync
#(
  parameter TDATA_WIDTH        = 32,
  parameter TUSER_WIDTH        = 1,
  parameter ADDR_WIDTH         = 9,
  parameter ALMOSTFULL_OFFSET  = 2,
  parameter ALMOSTEMPTY_OFFSET = 2
)
(
  input  wire                    i_clk,
  input  wire                    i_rstn,

  // write side
  input  wire                    i_tvalid,
  output wire                    o_tready,      // fifo not full/can accept data
  input  wire [TDATA_WIDTH-1:0]  i_tdata,
  input  wire [TUSER_WIDTH-1:0]  i_tuser,
  input  wire                    i_tlast,

  // read side
  output wire                    o_tvalid,
  input  wire                    i_tready,
  output reg  [TDATA_WIDTH-1:0]  o_tdata,
  output reg  [TUSER_WIDTH-1:0]  o_tuser,
  output reg                     o_tlast,

  // flags
  output reg  [ADDR_WIDTH:0]     o_fill,

  output wire                    o_full,
  output wire                    o_almostfull,
  output wire                    o_empty,
  output wire                    o_almostempty,

  output wire                    o_error
);

  localparam integer FIFO_DEPTH = (1 << ADDR_WIDTH);
  localparam integer WIDTH      = TDATA_WIDTH + TUSER_WIDTH + 1;

  reg [ADDR_WIDTH-1:0] wptr;
  reg [ADDR_WIDTH-1:0] rptr;

  reg [WIDTH-1:0] mem [0:FIFO_DEPTH-1];

  // --------------------------------------------------------------------------
  // Output register valid (this is the true "tvalid")
  // --------------------------------------------------------------------------
  reg out_valid;

  assign o_tvalid = out_valid;

  // Full/empty reflect total words available to read *including* the prefetched one.
  assign o_full        = (o_fill == FIFO_DEPTH);
  assign o_empty       = (o_fill == 0);
  assign o_almostfull  = (o_fill >= (FIFO_DEPTH - ALMOSTFULL_OFFSET));
  assign o_almostempty = (o_fill <= ALMOSTEMPTY_OFFSET);

  assign o_tready      = !o_full;

  // --------------------------------------------------------------------------
  // Handshake events (keep your naming)
  // wr_ok = actual accepted write
  // rd_ok = actual accepted read (transfer out)
  // --------------------------------------------------------------------------
  wire wr_ok = i_tvalid && o_tready;
  wire rd_ok = out_valid && i_tready;

  // --------------------------------------------------------------------------
  // Prefetch control:
  // If output register is empty and FIFO has stored words, pull next word into outputs.
  // "have_mem_data" means: there exists at least 1 word in memory not yet prefetched.
  // Since o_fill counts total words available including prefetched out_valid,
  // memory has data when (o_fill > out_valid).
  // --------------------------------------------------------------------------
  wire have_mem_data = (o_fill > (out_valid ? 1'b1 : 1'b0));
  wire do_prefetch   = (!out_valid) && have_mem_data;

  // Read the next memory word (combinational) at current rptr
  wire [WIDTH-1:0] mem_rd = mem[rptr];

  wire [TDATA_WIDTH-1:0] tdata_r = mem_rd[WIDTH-1 : TUSER_WIDTH+1];
  wire [TUSER_WIDTH-1:0] tuser_r = mem_rd[TUSER_WIDTH : 1];
  wire                   tlast_r = mem_rd[0];

  // --------------------------------------------------------------------------
  // Memory write
  // --------------------------------------------------------------------------
  always @(posedge i_clk) begin
    if (wr_ok) begin
      mem[wptr] <= {i_tdata, i_tuser, i_tlast};
    end
  end

  always @(posedge i_clk) begin
    if (!i_rstn) begin
      out_valid <= 1'b0;
      o_tdata   <= 1'b0;
      o_tuser   <= 1'b0;
      o_tlast   <= 1'b0;
    end else begin
      if (rd_ok) begin
        out_valid <= 1'b0;
      end

      if ( (!out_valid || rd_ok) && have_mem_data ) begin
        o_tdata   <= tdata_r;
        o_tuser   <= tuser_r;
        o_tlast   <= tlast_r;
        out_valid <= 1'b1;
      end
    end
  end

  always @(posedge i_clk) begin
    if (!i_rstn) begin
      wptr <= {ADDR_WIDTH{1'b0}};
    end else if (wr_ok) begin
      wptr <= wptr + 1'b1;
    end
  end

  always @(posedge i_clk) begin
    if (!i_rstn) begin
      rptr <= {ADDR_WIDTH{1'b0}};
    end else if ( ((!out_valid) || rd_ok) && have_mem_data ) begin
      rptr <= rptr + 1'b1;
    end
  end

  always @(posedge i_clk) begin
    if (!i_rstn) begin
      o_fill <= { (ADDR_WIDTH+1){1'b0} };
    end else begin
      case ({wr_ok, rd_ok})
        2'b10: o_fill <= o_fill + 1'b1; // push only
        2'b01: o_fill <= o_fill - 1'b1; // pop only (transfer out)
        default: o_fill <= o_fill;      // 00 or 11
      endcase
    end
  end

  wire underflow_attempt = i_tready && !o_tvalid;
  wire overflow_attempt  = i_tvalid && !o_tready;

  assign o_error = underflow_attempt || overflow_attempt;

endmodule
*/
module fifo_sync #(
  parameter TDATA_WIDTH = 32,
  parameter TUSER_WIDTH = 1,
  parameter ADDR_WIDTH  = 9
)(
  input  wire                    i_clk,
  input  wire                    i_rstn,

  // write side
  input  wire                    i_tvalid,
  output wire                    o_tready,
  input  wire [TDATA_WIDTH-1:0]  i_tdata,
  input  wire [TUSER_WIDTH-1:0]  i_tuser,
  input  wire                    i_tlast,

  // read side
  output reg                     o_tvalid,
  input  wire                    i_tready,
  output reg  [TDATA_WIDTH-1:0]  o_tdata,
  output reg  [TUSER_WIDTH-1:0]  o_tuser,
  output reg                     o_tlast,

  output wire                    o_full,
  output wire                    o_empty
);

  localparam integer WIDTH = TDATA_WIDTH + TUSER_WIDTH + 1;
  localparam integer DEPTH = (1 << ADDR_WIDTH);

  reg [WIDTH-1:0] mem [0:DEPTH-1];
  reg [ADDR_WIDTH-1:0] wptr, rptr;

  // count of words currently in *memory* (not including output register)
  reg [ADDR_WIDTH:0] mem_count;

  // write allowed when memory not full
  assign o_full   = (mem_count == DEPTH);
  assign o_tready = !o_full;

  // empty means no valid output beat AND memory empty
  assign o_empty  = (!o_tvalid) && (mem_count == 0);

  wire wr_ok   = i_tvalid && o_tready;

  // output beat consumed
  wire rd_ok   = o_tvalid && i_tready;

  // we should load output register when:
  // - output reg is empty, OR
  // - output reg is being consumed this cycle
  // and there is at least one word in memory
  wire load_out = ( (!o_tvalid) || rd_ok ) && (mem_count != 0);

  wire [WIDTH-1:0] mem_rd = mem[rptr];

  // --------------------------------------------------------------------------
  // Memory write
  // --------------------------------------------------------------------------
  always @(posedge i_clk) begin
    if (wr_ok) begin
      mem[wptr] <= {i_tdata, i_tuser, i_tlast};
    end
  end

  // --------------------------------------------------------------------------
  // Pointers + mem_count
  // mem_count tracks only memory occupancy; output reg is separate.
  // --------------------------------------------------------------------------
  always @(posedge i_clk) begin
    if (!i_rstn) begin
      wptr      <= 0;
      rptr      <= 0;
      mem_count <= 0;
    end else begin
      // advance write pointer
      if (wr_ok) begin
        wptr <= wptr + 1'b1;
      end

      // advance read pointer when we pull from memory into output reg
      if (load_out) begin
        rptr <= rptr + 1'b1;
      end

      // update mem_count:
      // wr_ok adds one word to memory
      // load_out removes one word from memory
      case ({wr_ok, load_out})
        2'b10: mem_count <= mem_count + 1'b1;
        2'b01: mem_count <= mem_count - 1'b1;
        default: mem_count <= mem_count;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Output register (this is where AXI HOLD must be guaranteed)
  // --------------------------------------------------------------------------
  always @(posedge i_clk) begin
    if (!i_rstn) begin
      o_tvalid <= 1'b0;
      o_tdata  <= 0;
      o_tuser  <= 0;
      o_tlast  <= 1'b0;
    end else begin
      if (load_out) begin
        // load next word from memory into output reg
        o_tvalid <= 1'b1;
        o_tdata  <= mem_rd[WIDTH-1 : TUSER_WIDTH+1];
        o_tuser  <= mem_rd[TUSER_WIDTH : 1];
        o_tlast  <= mem_rd[0];
      end else if (rd_ok) begin
        // consumed but nothing to replace => go empty
        o_tvalid <= 1'b0;
      end
      // else: hold stable while stalled
    end
  end

endmodule


