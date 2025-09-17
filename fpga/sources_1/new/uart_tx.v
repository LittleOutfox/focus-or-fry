module uart_tx (
    input clk,
    input start,
    input baud_tick,
    input reset,
    input [7:0] data,
    output reg tx_out,
    output reg tx_status //high = busy, low = ready
);

  localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
  parameter integer FRAME_BITS = 8;
  reg [1:0] state;
  reg [1:0] next_state = 0;
  reg [$clog2(FRAME_BITS) - 1:0] bit_index = 0;

  // Async reset w/ transition logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Combinational Logic for Next State
  always @(*) begin
    next_state = state;
    case (state)
    default: next_state = state;
    endcase
  end

  // Synchronous 
  always @(posedge clk or posedge reset) begin
    if (reset) begin
    end else begin
    end

endmodule
