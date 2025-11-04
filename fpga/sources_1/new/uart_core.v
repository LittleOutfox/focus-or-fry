module uart_core #(
    parameter integer WIDTH = 8,
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD = 115_200,
    parameter integer OVERSAMPLE = 16,
    parameter integer TX_FIFO_DEPTH = 64,
    parameter integer RX_FIFO_DEPTH = 64
) (
    // outwards interfacing ports
    input  wire clk,
    input  wire rx,
    output wire tx,

    // internal interface ports
    input wire reset,

    input wire read_uart,  //the "pop" signal for FIFO
    output wire [WIDTH - 1:0] read_data,
    output wire rx_empty,
    output wire rx_full,

    input wire [WIDTH - 1:0] write_data,
    input wire write_uart,
    output wire tx_full,
    output wire rx_frame_error
);

  wire baud_tick;
  wire tx_status;  //caution: high means busy, AND it could hold and dequeue multiple times
  wire [WIDTH - 1:0] tx_data_in;
  wire tx_start;  //needs to be flipped from empty
  wire rx_status;
  wire rx_valid;
  wire [WIDTH - 1:0] rx_data_out;
  wire rx_phase_arm;
  wire phase_first_tick;
  wire phase_center_tick;
  wire synced_rx;

  baud_generator #(
      .CLOCK_HZ   (CLOCK_HZ),
      .BAUD (BAUD),
      .OVERSAMPLE(OVERSAMPLE)
  ) u_baud_gen (
      .clk(clk),
      .enable(baud_tick)
  );

  //TX FIFO
  FIFO #(
      .WIDTH(WIDTH),
      .DEPTH(TX_FIFO_DEPTH)
  ) tx_fifo (
      .clk  (clk),
      .reset(reset),
      .enq  (write_uart),
      .din  (write_data),
      .deq  (~tx_status),
      .full (tx_full),
      .dout (tx_data_in),
      .empty(tx_start)
  );

  //RX FIFO
  FIFO #(
      .WIDTH(WIDTH),
      .DEPTH(RX_FIFO_DEPTH)
  ) rx_fifo (
      .clk  (clk),
      .reset(reset),
      .enq  (rx_valid),
      .din  (rx_data_out),
      .deq  (read_uart),
      .full (rx_full),
      .dout (read_data),
      .empty(rx_empty)
  );

  //only rx cares about the phase counter
  phase_counter #(
      .OVERSAMPLE(OVERSAMPLE)
  ) u_phase_counter (
      .baud_en(baud_tick),
      .clk(clk),
      .phase_arm(rx_phase_arm),
      .center_tick(phase_center_tick),
      .first_tick(phase_first_tick)
  );

  uart_rx_sync u_rx_sync (
      .async_in(rx),
      .clk(clk),
      .synced_input(synced_rx)
  );

  uart_rx #(
      .FRAME_BITS(WIDTH)
  ) u_uart_rx (
      .clk(clk),
      .rx_sync_in(synced_rx),
      .center_tick(phase_center_tick),
      .reset(reset),
      .rx_data(rx_data_out),
      .frame_error(rx_frame_error),
      .valid(rx_valid),
      .phase_arm(rx_phase_arm)
  );

  uart_tx #(
      .FRAME_BITS(WIDTH),
      .OVERSAMPLE(OVERSAMPLE)
  ) u_uart_tx (
      .clk(clk),
      .start(~tx_start),
      .baud_tick(baud_tick),
      .reset(reset),
      .tx_input(tx_data_in),
      .tx_out(tx),
      .tx_status(tx_status)
  );
endmodule
