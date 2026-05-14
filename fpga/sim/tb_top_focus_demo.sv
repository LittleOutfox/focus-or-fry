// need include statements for EDA playground
`include "top_focus_demo.v"
`include "uart_core.v"
`include "sync_2ff.v"
`include "FIFO.v"
`include "baud_generator.v"
`include "uart_rx.v"
`include "phase_counter.v"
`include "uart_tx.v"
`include "rolling_avg.v"
`include "focus_detector.v"

`timescale 1ns / 1ps

module tb_top_focus_demo;
  // top hardcodes 100 MHz clock and 115200 baud, so we sim at real timing
  localparam int CLK_HZ = 100_000_000;
  localparam int BAUD = 115_200;
  localparam int CLK_NS = 1e9 / CLK_HZ;  // 10 ns
  localparam int CLKS_PER_BIT = CLK_HZ / BAUD;  // 868 clocks per UART bit

  // DUT signals
  logic       clk;
  logic       reset_btn;
  logic       ack_btn;
  logic       uart_rx;
  wire        uart_tx;
  wire [7:0]  leds;

  // shared loop index
  int         i;
  int         t;

  // DUT -- override the slow real-board knobs so cooldown / heartbeat /
  // pulse stretcher are all visible inside a sub-millisecond simulation.
  // CLOCK_HZ + BAUD stay at real values so the bit-banged UART matches.
  top_focus_demo #(
      .COOLDOWN_TICKS(50),    // ~500 ns instead of 5 s
      .HB_BIT        (8),     // heartbeat toggles every 256 clks (~2.5 us)
      .STRETCH_TICKS (5000)   // ~50 us LED stretch instead of 0.25 s
  ) dut (
      .clk      (clk),
      .reset_btn(reset_btn),
      .ack_btn  (ack_btn),
      .uart_rx  (uart_rx),
      .uart_tx  (uart_tx),
      .leds     (leds)
  );

  // clk
  initial begin
    clk = 1'b0;
    forever #(CLK_NS / 2) clk = ~clk;
  end

  // waves
  initial begin
    $dumpfile("top_focus_demo.vcd");
    $dumpvars(0, tb_top_focus_demo);
  end

  // ------------ helpers ------------

  task wait_clocks(input int n);
    for (i = 0; i < n; i++) @(posedge clk);
  endtask

  // bit-bang one UART byte on uart_rx (8N1, LSB first, idle high)
  task uart_send_byte(input byte b);
    // small idle gap so back-to-back bytes look real
    uart_rx <= 1'b1;
    wait_clocks(5);

    // start bit
    uart_rx <= 1'b0;
    wait_clocks(CLKS_PER_BIT);

    // 8 data bits, LSB first
    for (i = 0; i < 8; i++) begin
      uart_rx <= b[i];
      wait_clocks(CLKS_PER_BIT);
    end

    // stop bit
    uart_rx <= 1'b1;
    wait_clocks(CLKS_PER_BIT);
  endtask

  // press ack_btn long enough for the focus_detector sync_2ff to see it
  task press_ack();
    @(posedge clk);
    ack_btn <= 1'b1;
    wait_clocks(8);
    ack_btn <= 1'b0;
  endtask

  task do_reset;
    reset_btn <= 1'b1;
    uart_rx   <= 1'b1;  // keep UART line idle during reset
    ack_btn   <= 1'b0;
    wait_clocks(10);
    reset_btn <= 1'b0;
    wait_clocks(5);
  endtask

  // verify a single led bit equals expected, fail otherwise
  task check_led(input int idx, input bit expected, input string msg);
    if (leds[idx] !== expected) begin
      $fatal(1, "[%0t] FAIL: %s -- leds[%0d]=%0d, expected=%0d", $time, msg, idx, leds[idx],
             expected);
    end
  endtask

  // poll leds[idx] until it equals expected, with a clock budget
  task wait_led(input int idx, input bit expected, input int max_clocks, input string msg);
    t = 0;
    while (leds[idx] !== expected && t < max_clocks) begin
      @(posedge clk);
      t++;
    end
    if (leds[idx] !== expected) begin
      $fatal(1, "[%0t] FAIL: %s -- leds[%0d]=%0d, expected=%0d after %0d clks", $time, msg, idx,
             leds[idx], expected, max_clocks);
    end
  endtask

  // ------------ main test ------------
  initial begin
    // init
    clk       = 1'b0;
    reset_btn = 1'b1;
    ack_btn   = 1'b0;
    uart_rx   = 1'b1;  // UART idles high

    wait_clocks(10);
    reset_btn = 1'b0;
    wait_clocks(5);

    // ---------------------------------------------------------------
    // TEST 1: after reset focused=1, focus_lost=0
    // (leds[5] = focused, leds[6] = focus_lost)
    // ---------------------------------------------------------------
    $display("[%0t] TEST1: after reset focused=1, focus_lost=0", $time);
    check_led(5, 1'b1, "TEST1 focused after reset");
    check_led(6, 1'b0, "TEST1 focus_lost after reset");
    $display("[%0t] TEST1: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 2: 4 healthy bytes (DEPTH=4) -> rolling_avg pulses,
    // focus_detector sees a high avg -> focused stays 1.
    // The pulse stretcher (leds[4]) latches on the first data_valid.
    // ---------------------------------------------------------------
    $display("[%0t] TEST2: 4 healthy bytes -> focused stays 1, dv stretched", $time);
    uart_send_byte(8'd80);
    uart_send_byte(8'd80);
    uart_send_byte(8'd80);
    uart_send_byte(8'd80);

    // give the FIFO -> rolling_avg pipeline a few clocks to drain
    wait_clocks(200);

    check_led(5, 1'b1, "TEST2 focused after 4 healthy bytes");
    check_led(6, 1'b0, "TEST2 focus_lost should still be 0");
    // pulse stretcher should be visible long after the one-clock data_valid
    check_led(4, 1'b1, "TEST2 dv_stretch_led should latch after 4 bytes");
    $display("[%0t] TEST2: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 3: low bytes drive focused to 0
    // start fresh so the rolling window is all low.
    // 4 low bytes warm up rolling_avg -> first data_valid: bad #1.
    // 5th low byte -> second data_valid: bad #2 = BAD_LIMIT -> trigger.
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST3: low bytes -> focused goes 0", $time);
    uart_send_byte(8'd30);
    uart_send_byte(8'd30);
    uart_send_byte(8'd30);
    uart_send_byte(8'd30);
    uart_send_byte(8'd30);

    // wait for rolling_avg + focus_detector pipeline to settle
    wait_led(5, 1'b0, 5000, "TEST3 expected focused=0 after 5 low bytes");
    check_led(6, 1'b1, "TEST3 focus_lost should be 1");
    $display("[%0t] TEST3: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 4: pressing ack_btn releases the focus-loss request.
    // focused returns to 1 once the FSM enters COOLDOWN.
    // (we do not wait the full 2 s cooldown -- only that focused goes high.)
    // ---------------------------------------------------------------
    $display("[%0t] TEST4: ack_btn releases focus-loss request", $time);
    press_ack();

    // 2 clks for sync_2ff + 1 clk state -> COOLDOWN, with margin
    wait_led(5, 1'b1, 50, "TEST4 expected focused=1 after ack");
    check_led(6, 1'b0, "TEST4 focus_lost should be 0 after ack");
    $display("[%0t] TEST4: PASS", $time);

    $display("[%0t] ALL TOP_FOCUS_DEMO TESTS PASS", $time);
    $finish;
  end

  // safety timeout. 5 bytes at 115200 baud ~ 435 us, plus reset/ack
  // overhead, well under 50 ms even with simulator slack.
  initial begin
    #50_000_000;  // 50 ms
    $display("[%0t] TIMEOUT: testbench did not complete in time", $time);
    $finish;
  end

endmodule
