`timescale 1ns / 1ps

module tb_focus_detector;
  // sim-friendly DUT parameters (no real 5-second cooldown)
  localparam int WIDTH = 8;
  localparam int THRESHOLD = 60;
  localparam int BAD_LIMIT = 3;
  localparam int COOLDOWN_TICKS = 6;

  // sim clock (period only matters for waveform readability)
  localparam int CLK_HZ = 100_000_000;
  localparam int CLK_NS = 10;

  // DUT signals
  logic             clk;
  logic             reset;
  logic             read_average;
  logic [WIDTH-1:0] avg_val;
  logic             acknowledge;
  wire              focused;

  int               i;

  focus_detector #(
      .WIDTH         (WIDTH),
      .THRESHOLD     (THRESHOLD),
      .CLOCK_HZ      (CLK_HZ),
      .COOLDOWN_TICKS(COOLDOWN_TICKS),
      .BAD_LIMIT     (BAD_LIMIT)
  ) dut (
      .clk         (clk),
      .reset       (reset),
      .read_average(read_average),
      .avg_val     (avg_val),
      .acknowledge (acknowledge),
      .focused     (focused)
  );

  // clk
  initial begin
    clk = 1'b0;
    forever #(CLK_NS / 2) clk = ~clk;
  end

  // waves
  initial begin
    $dumpfile("focus_detector.vcd");
    $dumpvars(0, tb_focus_detector);
  end

  // ------------ helpers ------------

  // wait n posedge clk
  task wait_clocks(input int n);
    for (i = 0; i < n; i++) @(posedge clk);
  endtask

  // drive one read_average pulse with the given avg value
  task pulse_average(input [WIDTH-1:0] value);
    @(posedge clk);
    avg_val      <= value;
    read_average <= 1'b1;
    @(posedge clk);
    read_average <= 1'b0;
  endtask

  // hold acknowledge high long enough for the 2-FF synchronizer to see it
  // (2 clocks for the synchronizer, 1 clock for the FSM to react, plus margin)
  task send_ack();
    @(posedge clk);
    acknowledge <= 1'b1;
    wait_clocks(4);
    acknowledge <= 1'b0;
  endtask

  // verify focused matches expected, fail with message otherwise
  task check_focused(input logic expected, input string message);
    if (focused !== expected) begin
      $fatal(1, "[%0t] FAIL: %s -- expected focused=%0d, got %0d", $time, message, expected,
             focused);
    end
  endtask

  // assert reset, drain TB drivers, release reset
  task do_reset;
    reset        <= 1'b1;
    read_average <= 1'b0;
    avg_val      <= '0;
    acknowledge  <= 1'b0;
    wait_clocks(5);
    reset <= 1'b0;
    wait_clocks(2);
  endtask

  // ------------ main test ------------
  initial begin
    // init signals
    reset        = 1'b1;
    read_average = 1'b0;
    avg_val      = '0;
    acknowledge  = 1'b0;

    wait_clocks(5);
    reset = 1'b0;
    wait_clocks(2);

    // ---------------------------------------------------------------
    // TEST 1: reset behavior -- focused should be 1 after reset
    // ---------------------------------------------------------------
    $display("[%0t] TEST1: after reset, focused should be 1", $time);
    check_focused(1'b1, "TEST1 after reset");
    $display("[%0t] TEST1: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 2: healthy averages never trigger focus loss
    // ---------------------------------------------------------------
    $display("[%0t] TEST2: healthy averages keep focused=1", $time);
    pulse_average(8'd80);
    wait_clocks(2);
    check_focused(1'b1, "TEST2 after avg=80");
    pulse_average(8'd75);
    wait_clocks(2);
    check_focused(1'b1, "TEST2 after avg=75");
    pulse_average(8'd70);
    wait_clocks(2);
    check_focused(1'b1, "TEST2 after avg=70");
    $display("[%0t] TEST2: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 3: 1 or 2 bad averages do not trigger (BAD_LIMIT = 3)
    // ---------------------------------------------------------------
    $display("[%0t] TEST3: 1-2 bad averages do not trigger", $time);
    pulse_average(8'd55);
    wait_clocks(2);
    check_focused(1'b1, "TEST3 after 1 bad");
    pulse_average(8'd54);
    wait_clocks(2);
    check_focused(1'b1, "TEST3 after 2 bad");
    $display("[%0t] TEST3: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 4: third consecutive bad average triggers focused=0
    // (continues from TEST3, count is already 2)
    // ---------------------------------------------------------------
    $display("[%0t] TEST4: 3rd consecutive bad triggers focused=0", $time);
    pulse_average(8'd53);
    wait_clocks(2);  // 1 clk for state -> TRIGGER, 1 clk for focused output
    check_focused(1'b0, "TEST4 after 3rd bad");
    $display("[%0t] TEST4: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 5: focused stays low until acknowledge, then returns to 1
    // ---------------------------------------------------------------
    $display("[%0t] TEST5: focused latched low until acknowledge", $time);
    wait_clocks(5);
    check_focused(1'b0, "TEST5 still low without ack");
    wait_clocks(5);
    check_focused(1'b0, "TEST5 still low without ack (longer)");

    send_ack();
    // send_ack returns the cycle that focused goes high (state has entered COOLDOWN)
    check_focused(1'b1, "TEST5 focused returns high after ack");
    $display("[%0t] TEST5: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 6: bad averages during cooldown must NOT retrigger
    // we are inside COOLDOWN right now (just rose after ack). Send the
    // 3 bads back-to-back so they fall inside the COOLDOWN_TICKS=6 window.
    // ---------------------------------------------------------------
    $display("[%0t] TEST6: bad averages during cooldown do not retrigger", $time);
    pulse_average(8'd55);
    check_focused(1'b1, "TEST6 cooldown bad #1");
    pulse_average(8'd54);
    check_focused(1'b1, "TEST6 cooldown bad #2");
    pulse_average(8'd53);
    check_focused(1'b1, "TEST6 cooldown bad #3");
    $display("[%0t] TEST6: PASS", $time);

    // ---------------------------------------------------------------
    // TEST 7: after cooldown, triggering works again
    // first send one good value to clear any partial bad count from
    // TEST 6 (some pulses may have spilled past cooldown into READ),
    // then wait out any remaining cooldown, then 3 bads -> trigger.
    // ---------------------------------------------------------------
    $display("[%0t] TEST7: after cooldown, 3 bad averages trigger again", $time);
    pulse_average(8'd80);  // resets count via FOCUSED state
    wait_clocks(COOLDOWN_TICKS + 5);  // make sure cooldown is fully done

    pulse_average(8'd50);
    wait_clocks(2);
    check_focused(1'b1, "TEST7 after 1 bad post-cooldown");
    pulse_average(8'd49);
    wait_clocks(2);
    check_focused(1'b1, "TEST7 after 2 bad post-cooldown");
    pulse_average(8'd48);
    wait_clocks(2);
    check_focused(1'b0, "TEST7 after 3 bad post-cooldown");
    $display("[%0t] TEST7: PASS", $time);

    // start TEST 8 from a known clean state
    do_reset();

    // ---------------------------------------------------------------
    // TEST 8: a good value resets the bad count
    //   bad, bad, good, bad, bad   -> NO trigger (count was reset)
    //   then 1 more bad            -> trigger (3 in a row after recovery)
    // ---------------------------------------------------------------
    $display("[%0t] TEST8: a good average resets the bad count", $time);
    pulse_average(8'd55);
    wait_clocks(2);
    check_focused(1'b1, "TEST8 bad #1");
    pulse_average(8'd54);
    wait_clocks(2);
    check_focused(1'b1, "TEST8 bad #2");
    pulse_average(8'd80);  // good value -> count reset
    wait_clocks(2);
    check_focused(1'b1, "TEST8 good resets count");
    pulse_average(8'd55);
    wait_clocks(2);
    check_focused(1'b1, "TEST8 bad #1 after recovery");
    pulse_average(8'd54);
    wait_clocks(2);
    check_focused(1'b1, "TEST8 bad #2 after recovery (still ok)");
    pulse_average(8'd53);
    wait_clocks(2);
    check_focused(1'b0, "TEST8 bad #3 after recovery should trigger");
    $display("[%0t] TEST8: PASS", $time);

    $display("[%0t] ALL FOCUS_DETECTOR TESTS PASS", $time);
    $finish;
  end

  // safety timeout
  initial begin
    #1_000_000;
    $display("[%0t] TIMEOUT: testbench did not complete in time", $time);
    $finish;
  end

endmodule
