`timescale 1ns / 1ps

module tb_uart_tx ();
  localparam int CLK_HZ = 100_000_000;  // 100 MHz
  localparam int BAUD = 115200;
  localparam int OVERSAMPLE = 16;
  localparam int CLK_NS = 10;  // 100 MHz -> 10 ns
  localparam int DIV = CLK_HZ / (OVERSAMPLE * BAUD);  // ~54
  localparam int FRAME_BITS = 8;

  // DUT I/O
  logic                  clk;
  logic                  reset;
  logic                  start;
  logic [FRAME_BITS-1:0] tx_input;
  logic                  baud_tick;
  logic                  tx_out;
  logic                  tx_status;  // 1 = busy, 0 = ready

  // For checking
  byte                   exp_byte;
  byte                   got_byte;
  int                    i;

  baud_generator #(
      .CLOCK_HZ  (CLK_HZ),
      .BAUD      (BAUD),
      .OVERSAMPLE(OVERSAMPLE)
  ) u_baud (
      .clk   (clk),
      .enable(baud_tick)
  );

  // your TX from /mnt/data/uart_tx.v
  uart_tx #(
      .FRAME_BITS(FRAME_BITS),
      .OVERSAMPLE(OVERSAMPLE)
  ) u_tx (
      .clk      (clk),
      .start    (start),
      .baud_tick(baud_tick),
      .reset    (reset),
      .tx_input (tx_input),
      .tx_out   (tx_out),
      .tx_status(tx_status)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_uart_tx);
  end

  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  // wait for N clock cycles
  task automatic wait_clocks(input int n);
    begin
      repeat (n) @(posedge clk);
    end
  endtask

  // wait for N baud ticks (the fast, oversample-rate ticks)
  task automatic wait_baud_ticks(input int n);
    int cnt;
    begin
      cnt = 0;
      while (cnt < n) begin
        @(posedge clk);
        if (baud_tick) cnt++;
      end
    end
  endtask

  // Send 1 byte to the TX: pulse start for 1 clk, set tx_input
  task automatic tx_send_byte(input byte b);
    begin
      // wait until TX is idle
      @(posedge clk);
      while (tx_status == 1'b1) @(posedge clk);

      tx_input <= b;
      start    <= 1'b1;
      @(posedge clk);
      start <= 1'b0;
    end
  endtask

  // Because the RTL uses OVERSAMPLE and advances state on
  // "baud_tick && sample_index == OVERSAMPLE-1", sample
  // in the middle of a bit by waiting OVERSAMPLE/2 baud ticks.
  task automatic rx_serial_from_tx(output byte b);
    int k;
    bit [FRAME_BITS-1:0] data_bits;
    begin
      // Wait for start bit to appear (line goes low)
      // (tx_out idles high)
      @(posedge clk);
      while (tx_out == 1'b1) @(posedge clk);

      // *edge* of the start bit, sample in the middle.
      wait_baud_ticks(OVERSAMPLE / 2);

      // sample START, should be 0
      if (tx_out !== 1'b0) begin
        $fatal(1, "[%0t] Expected start bit = 0, got %0b", $time, tx_out);
      end

      // Now read 8 data bits, LSB first
      for (k = 0; k < FRAME_BITS; k++) begin
        wait_baud_ticks(OVERSAMPLE);  // advance 1 full bit to its center
        data_bits[k] = tx_out;
      end

      // STOP BIT
      wait_baud_ticks(OVERSAMPLE);
      if (tx_out !== 1'b1) begin
        $fatal(1, "[%0t] Expected stop bit = 1, got %0b", $time, tx_out);
      end

      b = data_bits;
    end
  endtask

  initial begin
    // init
    start    = 0;
    tx_input = '0;
    reset    = 1;
    got_byte = 0;

    wait_clocks(5);
    reset = 0;
    wait_clocks(5);

    // ----------------------------------------------------
    // TEST 1: send 0x55
    // ----------------------------------------------------
    exp_byte = 8'h55;
    $display("[%0t] TEST1: send 0x%0h", $time, exp_byte);
    tx_send_byte(exp_byte);


    fork //fork allows procedural code to run in parallel (not critical to this TB just for safety and learning)
      begin  //thread 1 (waits for tx to return to idle)
        while (tx_status == 1'b1) begin // this is an impossible loop. simulation is event based so it will catch the same clock edge multiple times
          @(posedge clk);
        end
      end
      begin  //thread 2 capture what actually went out
        rx_serial_from_tx(got_byte);
      end
    join

    if (got_byte !== exp_byte) begin
      $fatal(1, "[%0t] TEST1 FAIL: expected 0x%0h, got 0x%0h", $time, exp_byte, got_byte);
    end else begin
      $display("[%0t] TEST1 PASS", $time);
    end

    // small gap to serperate tests
    wait_clocks(100);

    // ----------------------------------------------------
    // TEST 2: send 0xA5
    // ----------------------------------------------------
    exp_byte = 8'hA5;
    $display("[%0t] TEST2: send 0x%0h", $time, exp_byte);
    tx_send_byte(exp_byte);
    rx_serial_from_tx(got_byte);

    if (got_byte !== exp_byte) begin
      $fatal(1, "[%0t] TEST2 FAIL: expected 0x%0h, got 0x%0h", $time, exp_byte, got_byte);
    end else begin
      $display("[%0t] TEST2 PASS", $time);
    end

    // Final check: TX should be idle (wait out the stop bit)
    wait_baud_ticks(16);
    if (tx_status !== 1'b0) begin
      $fatal(1, "[%0t] Expected tx_status=0 (idle) at end", $time);
    end

    $display("[%0t] ALL TESTS PASSED :)", $time);
    $finish;
  end

endmodule
