
`default_nettype none
// MODIFICATIONS: 
// * Gated writes and reads
// * implemented axi-stream I/O
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


