// need include statements for EDA playground
`include "uart_core.v"
`include "uart_rx_sync.v"
`include "FIFO.v"
`include "baud_generator.v"
`include "uart_rx.v"
`include "phase_counter.v"
`include "uart_tx.v"

`timescale 1ns / 1ps

module tb_uart_core;
  // real parameters / constants (commented out for unreadable)
  // localparam int CLK_HZ = 100_000_000;
  // localparam int BAUD = 115_200;
  // localparam int OVERSAMPLE = 16;
  // localparam int CLK_NS = 1_000_000_000 / CLK_HZ;  // 10 ns
  // localparam int DIV = CLK_HZ / (BAUD * OVERSAMPLE);  // 100e6/(115200*16)=54
  // localparam int TICKS_PER_BIT = DIV * OVERSAMPLE;  // 54 * 16 = 864
  // localparam int WIDTH = 8;

  // smaller scaled constants for readability
  localparam int CLK_HZ = 1_000_000;  // 1 MHz instead of 100 MHz
  localparam int BAUD = 9600;  // slower baud for sim
  localparam int OVERSAMPLE = 4;  // keep moderate oversample
  localparam int WIDTH = 8;
  localparam int DIV = CLK_HZ / (BAUD * OVERSAMPLE);  // ~13
  localparam int TICKS_PER_BIT = DIV * OVERSAMPLE;  // 104
  localparam int CLK_NS = 1e9 / CLK_HZ;  // 1000 ns period (1 µs)


  // clock/reset
  logic             clk;
  logic             reset;

  // loopback / external RX drive
  logic             loopback_en;
  logic             rx_drive;
  wire              tx;
  wire              rx_line;

  // host-side interface
  logic             read_uart;
  logic [WIDTH-1:0] read_data;
  logic             rx_empty;
  logic             rx_full;

  logic [WIDTH-1:0] write_data;
  logic             write_uart;
  logic             tx_full;

  // status / error
  logic             rx_frame_error;
  bit               saw_frame_error;

  // test vectors (declared at top)
  byte exp0, exp1, exp2;
  byte got;

  // shared loop indices (declared at top to avoid in-block decls)
  int  i;
  int  k;

  // Wiring
  assign rx_line = (loopback_en) ? tx : rx_drive;

  // DUT
  uart_core #(
      .WIDTH        (WIDTH),
      .CLOCK_HZ     (CLK_HZ),
      .BAUD         (BAUD),
      .OVERSAMPLE   (OVERSAMPLE),
      .TX_FIFO_DEPTH(16),
      .RX_FIFO_DEPTH(16)
  ) dut (
      .clk  (clk),
      .rx   (rx_line),
      .tx   (tx),
      .reset(reset),

      .read_uart(read_uart),
      .read_data(read_data),
      .rx_empty (rx_empty),
      .rx_full  (rx_full),

      .write_data(write_data),
      .write_uart(write_uart),
      .tx_full   (tx_full),

      .rx_frame_error(rx_frame_error)
  );

  // clk
  initial begin
    clk = 1'b0;
    forever #(CLK_NS / 2) clk = ~clk;  // 5 ns high / 5 ns low
  end

  // optional waves
  initial begin
    $dumpfile("uart_core.vcd");
    $dumpvars(0, tb_uart_core);
  end

  task wait_clocks(input int n);
    for (i = 0; i < n; i++) @(posedge clk);
  endtask

  // push one byte to TX FIFO side
  task write_host_byte(input byte b);
    @(posedge clk);
    while (tx_full) @(posedge clk);
    write_data <= b;
    write_uart <= 1'b1;
    @(posedge clk);
    write_uart <= 1'b0;
  endtask

  // pop one byte from RX FIFO side
  task read_host_byte(output byte b);
    @(posedge clk);
    while (rx_empty) @(posedge clk);
    read_uart <= 1'b1;
    @(posedge clk);
    read_uart <= 1'b0;
    @(posedge clk);  // allow dout to present
    b = read_data;
  endtask

  // bit-bang a UART frame on rx_drive using DUT timing (optionally bad stop)
  task send_ext_byte(input byte b, input bit bad_stop);
    // idle high
    rx_drive <= 1'b1;
    wait_clocks(5);

    // start bit
    rx_drive <= 1'b0;
    wait_clocks(TICKS_PER_BIT);

    // data bits LSB->MSB
    for (i = 0; i < 8; i++) begin
      rx_drive <= b[i];
      wait_clocks(TICKS_PER_BIT);
    end

    // stop bit (bad_stop forces 0)
    rx_drive <= (bad_stop ? 1'b0 : 1'b1);
    wait_clocks(TICKS_PER_BIT);

    // back to idle
    rx_drive <= 1'b1;
    wait_clocks(TICKS_PER_BIT);
  endtask

  // Main test
  initial begin
    // init
    reset           = 1'b1;
    loopback_en     = 1'b0;
    rx_drive        = 1'b1;
    write_data      = '0;
    write_uart      = 1'b0;
    read_uart       = 1'b0;
    saw_frame_error = 0;

    // test bytes (declared at top, assigned here)
    exp0            = 8'h55;
    exp1            = 8'hA3;
    exp2            = 8'h00;

    wait_clocks(5);
    reset = 1'b0;
    wait_clocks(5);

    // --------------------------------------------
    // TEST 1: loopback TX->RX through core
    // --------------------------------------------
    $display("[%0t] TEST1: loopback TX->RX through core", $time);
    loopback_en = 1'b1;

    write_host_byte(exp0);
    write_host_byte(exp1);
    write_host_byte(exp2);

    read_host_byte(got);
    if (got !== exp0) $fatal(1, "[%0t] FAIL: expected %0h got %0h (byte0)", $time, exp0, got);

    read_host_byte(got);
    if (got !== exp1) $fatal(1, "[%0t] FAIL: expected %0h got %0h (byte1)", $time, exp1, got);

    read_host_byte(got);
    if (got !== exp2) $fatal(1, "[%0t] FAIL: expected %0h got %0h (byte2)", $time, exp2, got);

    $display("[%0t] TEST1: PASS", $time);

    // --------------------------------------------
    // TEST 2: inject bad stop -> expect frame_error pulse
    // --------------------------------------------
    $display("[%0t] TEST2: inject bad stop bit to test frame_error", $time);
    loopback_en = 1'b0;   // TB drives RX now
    rx_drive    = 1'b1;
    wait_clocks(10);

    send_ext_byte(8'hC1,  /*bad_stop*/ 1'b1);

    // watch for error pulse for a while
    for (k = 0; k < 2000; k++) begin
      @(posedge clk);
      if (rx_frame_error) saw_frame_error = 1;
    end

    if (!saw_frame_error) begin
      $fatal(1, "[%0t] FAIL: expected rx_frame_error pulse from DUT", $time);
    end else begin
      $display("[%0t] TEST2: PASS (rx_frame_error observed)", $time);
    end

    $display("[%0t] ALL TESTS PASS", $time);
    $finish;
  end

endmodule
