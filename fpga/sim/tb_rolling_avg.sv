`timescale 1ns / 1ps

module tb_rolling_avg;
  localparam int CLK_HZ = 1_000_000;  // 1 MHz sim clock
  localparam int CLK_NS = 1e9 / CLK_HZ;  // 1000 ns period

  // datapath
  localparam int WIDTH = 8;
  localparam int DEPTH = 8;  // rolling window depth
  localparam int IN_FIFO_DEPTH = 16;  // upstream FIFO feeding the DUT

  logic             clk;
  logic             reset;

  // upstream FIFO
  logic             enq_in;
  logic [WIDTH-1:0] din_in;
  wire  [WIDTH-1:0] dout_in;
  wire              full_in;
  wire              empty_in;

  wire              read_attention;

  // rolling_avg outputs
  wire              data_valid;
  wire  [WIDTH-1:0] avg_val;

  // bookkeeping
  bit               data_valid_seen;
  int               data_valid_count;
  logic [WIDTH-1:0] last_avg;
  logic [WIDTH-1:0] min_avg_seen;
  logic [WIDTH-1:0] max_avg_seen;
  int               i;
  int               timeout_cnt;

  // upstream FIFO acts as the attention queue (e.g. fed by packet_rx in real use).
  // Real FIFO instance so deq/dout/empty timing is exercised correctly.
  FIFO #(
      .WIDTH(WIDTH),
      .DEPTH(IN_FIFO_DEPTH)
  ) feed_fifo (
      .clk  (clk),
      .reset(reset),
      .enq  (enq_in),
      .din  (din_in),
      .deq  (read_attention),
      .full (full_in),
      .dout (dout_in),
      .empty(empty_in)
  );

  rolling_avg #(
      .WIDTH(WIDTH),
      .DEPTH(DEPTH)
  ) dut (
      .clk           (clk),
      .reset         (reset),
      .data_valid    (data_valid),
      .avg_val       (avg_val),
      .read_attention(read_attention),
      .empty         (empty_in),
      .attention     (dout_in)
  );

  // clk
  initial begin
    clk = 1'b0;
    forever #(CLK_NS / 2) clk = ~clk;
  end

  // waves
  initial begin
    $dumpfile("rolling_avg.vcd");
    $dumpvars(0, tb_rolling_avg);
  end

  // latch every data_valid pulse so tests can check asynchronously.
  // also tracks min/max of every avg_val ever observed since last clear_flags --
  // useful to assert "every avg seen was X" in stress tests.
  always @(posedge clk) begin
    if (data_valid) begin
      data_valid_seen <= 1'b1;
      data_valid_count <= data_valid_count + 1;
      last_avg <= avg_val;
      if (avg_val < min_avg_seen) min_avg_seen <= avg_val;
      if (avg_val > max_avg_seen) max_avg_seen <= avg_val;
    end
  end

  // ------------ helpers ------------
  task wait_clocks(input int n);
    for (i = 0; i < n; i++) @(posedge clk);
  endtask

  task clear_flags;
    data_valid_seen  = 1'b0;
    data_valid_count = 0;
    last_avg         = '0;
    min_avg_seen     = '1;  // start at max so first sample sets it
    max_avg_seen     = '0;
  endtask

  // enqueue one byte into the upstream FIFO
  task push_byte(input byte b);
    @(posedge clk);
    while (full_in) @(posedge clk);
    din_in <= b;
    enq_in <= 1'b1;
    @(posedge clk);
    enq_in <= 1'b0;
  endtask

  // wait until at least n data_valid pulses have been observed (since last clear_flags)
  task wait_for_n_valid(input int n, input int max_cycles);
    timeout_cnt = 0;
    while (data_valid_count < n && timeout_cnt < max_cycles) begin
      @(posedge clk);
      timeout_cnt++;
    end
    if (data_valid_count < n)
      $fatal(
          1,
          "[%0t] FAIL: timeout waiting for %0d data_valid pulses (got %0d) after %0d cycles",
          $time,
          n,
          data_valid_count,
          max_cycles
      );
  endtask

  // assert reset, drain TB-side drivers, clear flags
  task do_reset;
    reset  <= 1'b1;
    enq_in <= 1'b0;
    din_in <= '0;
    clear_flags();
    wait_clocks(5);
    reset <= 1'b0;
    wait_clocks(5);
  endtask

  // ------------ main test ------------
  initial begin
    // init
    reset            = 1'b1;
    enq_in           = 1'b0;
    din_in           = '0;
    data_valid_seen  = 1'b0;
    data_valid_count = 0;
    last_avg         = '0;
    min_avg_seen     = '1;
    max_avg_seen     = '0;

    wait_clocks(5);
    reset = 1'b0;
    wait_clocks(5);

    // ---------------------------------------------------------------
    // TEST 1: window of identical values -> avg equals that value,
    //         exactly one data_valid pulse on the DEPTH-th sample
    // ---------------------------------------------------------------
    $display("[%0t] TEST1: push 8 copies of 0x40 -> expect avg=0x40, exactly 1 data_valid pulse",
             $time);
    clear_flags();

    for (int k = 0; k < DEPTH; k++) push_byte(8'h40);

    wait_for_n_valid(1, 500);
    // give a little extra time so any spurious extra pulse would be caught
    wait_clocks(20);

    if (last_avg !== 8'h40)
      $fatal(1, "[%0t] FAIL TEST1: expected avg=0x40, got 0x%0h", $time, last_avg);
    if (data_valid_count !== 1)
      $fatal(1, "[%0t] FAIL TEST1: expected 1 data_valid pulse, got %0d", $time, data_valid_count);
    $display("[%0t] TEST1: PASS (avg=0x%0h, pulses=%0d)", $time, last_avg, data_valid_count);

    // ---------------------------------------------------------------
    // TEST 2: warm-up -- fewer than DEPTH samples must NOT pulse data_valid
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST2: push only 3 < DEPTH samples -> expect NO data_valid", $time);

    push_byte(8'h10);
    push_byte(8'h20);
    push_byte(8'h30);

    wait_clocks(80);  // plenty of time for DUT to finish consuming

    if (data_valid_seen)
      $fatal(1, "[%0t] FAIL TEST2: data_valid pulsed before window was full", $time);
    $display("[%0t] TEST2: PASS (no data_valid before window full)", $time);

    // ---------------------------------------------------------------
    // TEST 3: known mixed values -> verify avg = sum/DEPTH
    // 0x08+0x10+0x18+0x20+0x28+0x30+0x38+0x40 = 0x120 (288)
    // 0x120 >> 3 = 0x24 (36)
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST3: 8 known values -> expect avg=0x24", $time);

    push_byte(8'h08);
    push_byte(8'h10);
    push_byte(8'h18);
    push_byte(8'h20);
    push_byte(8'h28);
    push_byte(8'h30);
    push_byte(8'h38);
    push_byte(8'h40);

    wait_for_n_valid(1, 500);

    if (last_avg !== 8'h24)
      $fatal(1, "[%0t] FAIL TEST3: expected avg=0x24, got 0x%0h", $time, last_avg);
    $display("[%0t] TEST3: PASS (avg=0x%0h)", $time, last_avg);

    // ---------------------------------------------------------------
    // TEST 4: rolling -- continuing from TEST3, push 0x48.
    // new sum = 0x120 - 0x08 (oldest) + 0x48 = 0x160 (352)
    // 0x160 >> 3 = 0x2C (44)
    // ---------------------------------------------------------------
    $display("[%0t] TEST4: push 1 more value -> rolling window evicts oldest, expect avg=0x2C",
             $time);
    clear_flags();
    push_byte(8'h48);

    wait_for_n_valid(1, 500);

    if (last_avg !== 8'h2C)
      $fatal(1, "[%0t] FAIL TEST4: expected avg=0x2C, got 0x%0h", $time, last_avg);
    $display("[%0t] TEST4: PASS (avg=0x%0h after rolling)", $time, last_avg);

    // ---------------------------------------------------------------
    // TEST 5: reset mid-stream clears state; later avg unaffected by pre-reset data
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST5: partial fill, reset, then full window of 0x20 -> expect avg=0x20",
             $time);

    push_byte(8'h50);
    push_byte(8'h50);
    push_byte(8'h50);

    do_reset();

    for (int k = 0; k < DEPTH; k++) push_byte(8'h20);

    wait_for_n_valid(1, 500);

    if (last_avg !== 8'h20)
      $fatal(1, "[%0t] FAIL TEST5: expected avg=0x20 after reset, got 0x%0h", $time, last_avg);
    if (data_valid_count !== 1)
      $fatal(
          1,
          "[%0t] FAIL TEST5: expected exactly 1 data_valid post-reset, got %0d",
          $time,
          data_valid_count
      );
    $display("[%0t] TEST5: PASS (avg=0x%0h after reset, pulses=%0d)", $time, last_avg,
             data_valid_count);

    // ---------------------------------------------------------------
    // TEST 6: gaps in the upstream feed -- DUT must idle, then resume,
    //         and avg must be correct across the gap
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST6: gappy feed of 8 copies of 0x10 -> expect avg=0x10", $time);

    for (int k = 0; k < DEPTH; k++) begin
      push_byte(8'h10);
      wait_clocks(20);  // force upstream-empty stalls between samples
    end

    wait_for_n_valid(1, 1000);

    if (last_avg !== 8'h10)
      $fatal(1, "[%0t] FAIL TEST6: expected avg=0x10, got 0x%0h", $time, last_avg);
    $display("[%0t] TEST6: PASS (avg=0x%0h despite stalls)", $time, last_avg);

    // ---------------------------------------------------------------
    // TEST 7: OVERFLOW STRESS -- stream 64 copies of 0xFF.
    // Window is always full of 0xFF, so EVERY avg pulse must read 0xFF.
    // Expect (64 - DEPTH + 1) = 57 valid pulses; check min/max of all
    // observed avgs to confirm no overflow, no truncation, no drift.
    // ---------------------------------------------------------------
    do_reset();
    $display("[%0t] TEST7: stress 64x 0xFF -> every avg must be 0xFF (overflow check)", $time);

    for (int k = 0; k < 64; k++) push_byte(8'hFF);

    wait_for_n_valid(57, 5000);
    wait_clocks(20);  // catch any straggler pulse

    if (last_avg !== 8'hFF)
      $fatal(1, "[%0t] FAIL TEST7: last avg expected 0xFF, got 0x%0h", $time, last_avg);
    if (min_avg_seen !== 8'hFF || max_avg_seen !== 8'hFF)
      $fatal(
          1,
          "[%0t] FAIL TEST7: avg deviated from 0xFF (min=0x%0h max=0x%0h) -- overflow/wrap?",
          $time,
          min_avg_seen,
          max_avg_seen
      );
    if (data_valid_count < 57)
      $fatal(1, "[%0t] FAIL TEST7: expected >=57 pulses, got %0d", $time, data_valid_count);
    $display("[%0t] TEST7: PASS (no overflow; %0d pulses, min=0x%0h max=0x%0h last=0x%0h)", $time,
             data_valid_count, min_avg_seen, max_avg_seen, last_avg);

    $display("[%0t] ALL ROLLING_AVG TESTS PASS", $time);
    $finish;
  end

  // safety timeout
  initial begin
    #100000000;
    $display("[%0t] TIMEOUT: testbench did not complete in time", $time);
    $finish;
  end

endmodule
