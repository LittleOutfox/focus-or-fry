`timescale 1ns / 1ps

module tb_packet_rx;
  // clock
  localparam int CLK_HZ = 1_000_000;  // 1 MHz sim clock
  localparam int CLK_NS = 1e9 / CLK_HZ;  // 1000 ns period

  // datapath
  localparam int WIDTH = 8;
  localparam int IN_FIFO_DEPTH = 16;  // upstream "UART RX" FIFO
  localparam int OUT_FIFO_DEPTH = 4;  // small DUT output FIFO so full/error is easy to hit

  // clock/reset
  logic             clk;
  logic             reset;

  // upstream input FIFO -- TB drives the enq side
  logic             enq_in;
  logic [WIDTH-1:0] din_in;
  wire  [WIDTH-1:0] dout_in;
  wire              full_in;
  wire              empty_in;

  // packet_rx <-> input FIFO
  wire              read_uart;  // DUT pop request -> input FIFO deq

  // packet_rx output side
  logic             deq_out;
  wire              full_out;
  wire              empty_out;
  wire  [WIDTH-1:0] attention;
  wire              dut_error;

  // bookkeeping
  bit               error_seen;
  byte              got;
  int               i;
  int               k;
  int               timeout_cnt;

  // upstream input FIFO acts as the UART RX FIFO feeding packet_rx.
  // We use a real FIFO instance (not faked combinationally) so timing
  // between read_uart, dout_in and rx_empty is exercised correctly.
  FIFO #(
      .WIDTH(WIDTH),
      .DEPTH(IN_FIFO_DEPTH)
  ) uart_rx_fifo (
      .clk  (clk),
      .reset(reset),
      .enq  (enq_in),
      .din  (din_in),
      .deq  (read_uart),
      .full (full_in),
      .dout (dout_in),
      .empty(empty_in)
  );

  // DUT
  packet_rx #(
      .WIDTH     (WIDTH),
      .FIFO_DEPTH(OUT_FIFO_DEPTH)
  ) dut (
      .clk      (clk),
      .reset    (reset),
      .read_uart(read_uart),
      .data     (dout_in),
      .rx_empty (empty_in),
      .deq      (deq_out),
      .full     (full_out),
      .empty    (empty_out),
      .attention(attention),
      .error    (dut_error)
  );

  // clk
  initial begin
    clk = 1'b0;
    forever #(CLK_NS / 2) clk = ~clk;
  end

  // waves
  initial begin
    $dumpfile("packet_rx.vcd");
    $dumpvars(0, tb_packet_rx);
  end

  // continuously latch any DUT error pulse so we can check it asynchronously
  always @(posedge clk) begin
    if (dut_error) error_seen <= 1'b1;
  end

  // ------------ helpers ------------
  task wait_clocks(input int n);
    for (i = 0; i < n; i++) @(posedge clk);
  endtask

  task clear_flags;
    error_seen = 1'b0;
  endtask

  function automatic byte checksum(input byte seq, input byte attention);
    checksum = 8'hAA ^ seq ^ attention;
  endfunction

  // enqueue one byte into the upstream input FIFO
  task push_uart_byte(input byte b);
    @(posedge clk);
    while (full_in) @(posedge clk);
    din_in <= b;
    enq_in <= 1'b1;
    @(posedge clk);
    enq_in <= 1'b0;
  endtask

  // push a complete valid packet: AA, seq, attn, checksum
  task push_packet(input byte seq, input byte attn);
    push_uart_byte(8'hAA);
    push_uart_byte(seq);
    push_uart_byte(attn);
    push_uart_byte(checksum(seq, attn));
  endtask

  // wait until DUT output FIFO has at least one entry, with timeout
  task wait_for_not_empty(input int max_cycles);
    timeout_cnt = 0;
    while (empty_out && timeout_cnt < max_cycles) begin
      @(posedge clk);
      timeout_cnt++;
    end
    if (empty_out)
      $fatal(
          1,
          "[%0t] FAIL: timeout waiting for DUT output FIFO non-empty after %0d cycles",
          $time,
          max_cycles
      );
  endtask

  // wait until error_seen is set or timeout (no fail on timeout -- caller decides)
  task wait_for_error(input int max_cycles);
    timeout_cnt = 0;
    while (!error_seen && timeout_cnt < max_cycles) begin
      @(posedge clk);
      timeout_cnt++;
    end
  endtask

  // pulse DUT deq for one cycle, wait one extra clock for FIFO dout to settle, then sample
  task pop_attention(output byte b);
    @(posedge clk);
    while (empty_out) @(posedge clk);
    deq_out <= 1'b1;
    @(posedge clk);
    deq_out <= 1'b0;
    @(posedge clk);  // allow dout to present
    b = attention;
  endtask

  // assert reset, drain TB-side drivers, clear flags
  task do_reset;
    reset   <= 1'b1;
    enq_in  <= 1'b0;
    din_in  <= '0;
    deq_out <= 1'b0;
    clear_flags();
    wait_clocks(5);
    reset <= 1'b0;
    wait_clocks(5);
  endtask

  // ------------ main test ------------
  initial begin
    // init
    reset      = 1'b1;
    enq_in     = 1'b0;
    din_in     = '0;
    deq_out    = 1'b0;
    error_seen = 1'b0;

    wait_clocks(5);
    reset = 1'b0;
    wait_clocks(5);

    // ---------------------------------------------------------------
    // TEST 1: single valid packet -> attention 0x48 should appear
    // ---------------------------------------------------------------
    $display("[%0t] TEST1: single valid packet AA 03 48 E1 -> expect attention=0x48", $time);
    clear_flags();

    push_uart_byte(8'hAA);
    push_uart_byte(8'h03);
    push_uart_byte(8'h48);
    push_uart_byte(8'hE1);  // AA ^ 03 ^ 48 = E1

    wait_for_not_empty(500);
    pop_attention(got);

    if (got !== 8'h48)
      $fatal(1, "[%0t] FAIL TEST1: expected attention 0x48, got 0x%0h", $time, got);
    if (error_seen)
      $fatal(1, "[%0t] FAIL TEST1: unexpected error pulse during valid packet", $time);
    $display("[%0t] TEST1: PASS (attention=0x%0h)", $time, got);

    // ---------------------------------------------------------------
    // TEST 2: garbage bytes before AA must be discarded; valid packet still parsed
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST2: garbage 12 99 then valid AA 04 40 cs -> expect attention=0x40", $time);

    push_uart_byte(8'h12);
    push_uart_byte(8'h99);
    push_uart_byte(8'hAA);
    push_uart_byte(8'h04);
    push_uart_byte(8'h40);
    push_uart_byte(checksum(8'h04, 8'h40));

    wait_for_not_empty(500);
    pop_attention(got);

    if (got !== 8'h40)
      $fatal(1, "[%0t] FAIL TEST2: expected attention 0x40, got 0x%0h", $time, got);
    $display("[%0t] TEST2: PASS (attention=0x%0h)", $time, got);

    // ---------------------------------------------------------------
    // TEST 3: bad checksum -> error pulse, output FIFO stays empty
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST3: bad checksum -> expect error, no enqueue", $time);

    push_uart_byte(8'hAA);
    push_uart_byte(8'h03);
    push_uart_byte(8'h48);
    push_uart_byte(8'h00);  // wrong checksum (should be E1)

    wait_for_error(500);

    if (!error_seen) $fatal(1, "[%0t] FAIL TEST3: expected error pulse but none observed", $time);
    if (!empty_out) $fatal(1, "[%0t] FAIL TEST3: output FIFO not empty after bad checksum", $time);
    $display("[%0t] TEST3: PASS (error observed, output FIFO still empty)", $time);

    // ---------------------------------------------------------------
    // TEST 4: two valid packets in a row -> 0x10, 0x20 in order
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST4: two valid packets back-to-back -> expect 0x10 then 0x20", $time);

    push_packet(8'h01, 8'h10);
    push_packet(8'h02, 8'h20);

    wait_for_not_empty(500);
    pop_attention(got);
    if (got !== 8'h10)
      $fatal(1, "[%0t] FAIL TEST4: first attention expected 0x10, got 0x%0h", $time, got);

    wait_for_not_empty(500);
    pop_attention(got);
    if (got !== 8'h20)
      $fatal(1, "[%0t] FAIL TEST4: second attention expected 0x20, got 0x%0h", $time, got);
    $display("[%0t] TEST4: PASS (0x10 then 0x20, order preserved)", $time);

    // ---------------------------------------------------------------
    // TEST 5: fill output FIFO (depth=4) -> overflow attempt -> error,
    //         original 4 entries must remain intact and in order
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST5: fill output FIFO (depth=%0d) and verify overflow -> error", $time,
             OUT_FIFO_DEPTH);

    push_packet(8'h01, 8'h11);
    push_packet(8'h02, 8'h22);
    push_packet(8'h03, 8'h33);
    push_packet(8'h04, 8'h44);

    // wait until output FIFO reports full
    timeout_cnt = 0;
    while (!full_out && timeout_cnt < 2000) begin
      @(posedge clk);
      timeout_cnt++;
    end
    if (!full_out) $fatal(1, "[%0t] FAIL TEST5: output FIFO never reached full", $time);

    // push a 5th valid packet -- DUT must pulse error and not corrupt the FIFO
    clear_flags();
    push_packet(8'h05, 8'h55);
    wait_for_error(500);
    if (!error_seen) $fatal(1, "[%0t] FAIL TEST5: expected error pulse on overflow attempt", $time);

    // dequeue the 4 originally-stored values, verify untouched and in order
    pop_attention(got);
    if (got !== 8'h11) $fatal(1, "[%0t] FAIL TEST5: byte0 expected 0x11, got 0x%0h", $time, got);
    pop_attention(got);
    if (got !== 8'h22) $fatal(1, "[%0t] FAIL TEST5: byte1 expected 0x22, got 0x%0h", $time, got);
    pop_attention(got);
    if (got !== 8'h33) $fatal(1, "[%0t] FAIL TEST5: byte2 expected 0x33, got 0x%0h", $time, got);
    pop_attention(got);
    if (got !== 8'h44) $fatal(1, "[%0t] FAIL TEST5: byte3 expected 0x44, got 0x%0h", $time, got);

    $display("[%0t] TEST5: PASS (overflow rejected, original 4 preserved)", $time);

    $display("[%0t] ALL PACKET_RX TESTS PASS", $time);
    $finish;
  end

  // safety timeout
  initial begin
    #100000000;
    $display("[%0t] TIMEOUT: testbench did not complete in time", $time);
    $finish;
  end

endmodule
