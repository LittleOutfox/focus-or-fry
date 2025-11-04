`timescale 1ns / 1ps
module tb_phase_counter ();
  localparam int OVERSAMPLE = 16;  // you can try 8 to speed up sims
  localparam int CENTER = OVERSAMPLE / 2;

  // DUT signals
  logic clk = 0;
  logic baud_en = 0;
  logic phase_arm = 0;
  wire  center_tick;
  wire  first_tick;

  int   start_idx;
  int   until_idx;

  phase_counter #(
      .OVERSAMPLE(OVERSAMPLE)
  ) dut (
      .baud_en(baud_en),
      .clk(clk),
      .phase_arm(phase_arm),
      .center_tick(center_tick),
      .first_tick(first_tick)
  );

  // creating the clock
  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  int cycles = 0;
  always @(posedge clk) cycles++;

  // one baud_en pulse on a posedge clk
  task automatic pulse_baud(int n = 1);
    for (int i = 0; i < n; i++) begin
      @(posedge clk);
      baud_en <= 1'b1;
      @(posedge clk);
      baud_en <= 1'b0;
    end
  endtask

  // VCD dump
  initial begin
    $dumpfile("tb_phase_counter.vcd");
    $dumpvars(0);
  end

  // check single-cycle pulse
  task automatic check_onehot_pulse(string name, logic sig);
    static logic prev_center, prev_first;
    if (name == "center") begin
      if (sig && prev_center) $fatal(1, "[%0t] center_tick wider than 1 clk", $time);
      prev_center = sig;
    end else begin
      if (sig && prev_first) $fatal(1, "[%0t] first_tick wider than 1 clk", $time);
      prev_first = sig;
    end
  endtask

  // track events on each clk edge for pulse width
  always @(posedge clk) begin
    check_onehot_pulse("center", center_tick);
    check_onehot_pulse("first", first_tick);
  end

  // scoreboard: measure distances in baud_en domain
  int last_first_idx = -1;
  int last_center_idx = -1;
  int baud_idx = 0;
  int delta;
  int firsts = 0, centers = 0;

  // increment baud index at each asserted enable (aligned to posedge clk)
  always @(posedge clk) begin
    if (baud_en) baud_idx++;
  end

  // latch when pulses occur to check spacing
  always @(posedge clk) begin
    if (first_tick) begin
      if (last_first_idx >= 0) begin
        delta = baud_idx - last_first_idx;
        if (delta != OVERSAMPLE)
          $fatal(1, "[%0t] First->First spacing %0d != OVERSAMPLE %0d", $time, delta, OVERSAMPLE);
      end
      last_first_idx = baud_idx;
    end
    if (center_tick) begin
      if (last_first_idx >= 0) begin
        delta = baud_idx - last_first_idx;
        if (delta != CENTER)
          $fatal(1, "[%0t] First->Center spacing %0d != CENTER %0d", $time, delta, CENTER);
      end
      if (first_tick && CENTER != 0)
        $fatal(1, "[%0t] center_tick coincident with first_tick unexpectedly", $time);
      last_center_idx = baud_idx;
    end
  end

  logic seen_center;
  // main stimulus
  initial begin
    $display("=== tb_phase_counter start (OVERSAMPLE=%0d) ===", OVERSAMPLE);

    // idle: while phase_arm is HELD high, no ticks should appear
    phase_arm = 1'b1;
    pulse_baud(10);
    if (first_tick || center_tick) $fatal(1, "Ticks appeared while phase_arm held high");
    phase_arm = 1'b0;  // release

    // pulse phase_arm, then expect first_tick on the very next enable
    phase_arm = 1'b1;
    @(posedge clk);
    phase_arm = 1'b0;  // RELEASE so counting can proceed
    pulse_baud(1);
    @(posedge clk);
    if (!first_tick) $fatal(1, "No first_tick on first enable after phase_arm pulse");

    // complete the rest of a frame and watch for center as a single-cycle pulse
    seen_center = 0;
    for (int i = 0; i < OVERSAMPLE - 1; i++) begin
      pulse_baud(1);
      @(posedge clk) if (center_tick) seen_center = 1;
    end
    if (!seen_center) $fatal(1, "No center_tick seen within the first frame");

    // another full frame: expect exactly one first and one center
    firsts = 0;
    centers = 0;
    start_idx = baud_idx;
    until_idx = start_idx + OVERSAMPLE;

    while (baud_idx < until_idx) begin
      pulse_baud(1);
      @(posedge clk) if (first_tick) firsts++;
      if (center_tick) centers++;
    end
    if (firsts != 1 || centers != 1)
      $fatal(
          1, "Expected 1 first and 1 center in a frame, got first=%0d center=%0d", firsts, centers
      );

    // hold baud_en low: counter must not advance, no ticks
    repeat (10) @(posedge clk);
    if (first_tick || center_tick) $fatal(1, "Ticks appeared while baud_en=0");

    // start a partial frame, then re-arm with a pulse; next enable should realign to first
    pulse_baud(CENTER / 2);  // mid progress
    // pulse re-arm and invalidate spacing references (aborted frame)
    phase_arm = 1'b1;
    @(posedge clk);
    phase_arm = 1'b0;
    last_first_idx = -1;
    last_center_idx = -1;
    @(posedge clk);
    pulse_baud(1);
    @(posedge clk);
    if (!first_tick) $fatal(1, "Expected first_tick after mid-frame phase_arm pulse");

    // multi-frame sanity: 3 frames => 3 firsts & 3 centers
    firsts  = 0;
    centers = 0;
    for (int f = 0; f < 3; f++) begin
      for (int i = 0; i < OVERSAMPLE; i++) begin
        pulse_baud(1);
        @(posedge clk);
        if (first_tick) firsts++;
        if (center_tick) centers++;
      end
    end
    if (firsts != 3 || centers != 3)
      $fatal(1, "Across 3 frames expected 3 first/3 center, got %0d/%0d", firsts, centers);

    $display("=== PASS: tb_phase_counter ===");
    $finish;
  end
endmodule
