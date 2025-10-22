`timescale 1ns/1ps

module tb_baud_generator ();
  //bookkeeping
  integer cycle_count = 0;
  integer last_tick_cycle = -1;
  integer tick_count = 0;
  integer high_len = 0;
  integer period;
  reg enable_q = 0;
  reg clk;

  // sim params: pick a small DIV to keep sims fast
  localparam integer DIV_UNDER_TEST = 8;

  // creating the clock
  initial begin
      clk = 0;
      forever begin
          #5 clk = ~clk;
      end
  end

  // DUT
  wire enable;
  baud_generator #(
    .CLOCK_HZ(100_000_000), // irrelevant for this TB since we override DIV
    .BAUD(115_200),
    .OVERSAMPLE(16),
    .DIV(DIV_UNDER_TEST)
  ) dut (
    .clk(clk),
    .enable(enable)
  );

  initial begin
    $dumpfile("tb_baud_generator.vcd");
    $dumpvars(0, tb_baud_generator);
  end

  // assertions/checks on each clock
  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    // track pulse width (must be exactly 1 cycle)
    enable_q <= enable;
    if (enable) begin
      high_len <= high_len + 1;
      if (high_len > 1) begin
        $display("[%0t] ERROR: enable stayed high for %0d cycles (>1)", $time, high_len);
        $fatal(1);
      end
    end else if (enable_q && !enable) begin
      // falling edge: verify width==1
      if (high_len != 1) begin
        $display("[%0t] ERROR: enable width was %0d, expected 1", $time, high_len);
        $fatal(1);
      end
      high_len <= 0;
    end

    // detect rising edge and check period
    if (!enable_q && enable) begin
      if (last_tick_cycle >= 0) begin
        period = cycle_count - last_tick_cycle;
        if (period !== DIV_UNDER_TEST) begin
          $display("[%0t] ERROR: tick period %0d != DIV %0d", $time, period, DIV_UNDER_TEST);
          $display("[%0t] DEBUG: expected DIV=%0d, measured period=%0d", $time, DIV_UNDER_TEST, period);
          $fatal(1);
        end
      end
      last_tick_cycle <= cycle_count;
      tick_count <= tick_count + 1;

      // stop after several good ticks
      if (tick_count == 10) begin
        $display("[%0t] PASS: saw %0d clean ticks, period=%0d, width=1", $time, tick_count, DIV_UNDER_TEST);
        $finish;
      end
    end
  end

  // safety timeout
  initial begin
    #100000;
    $display("[%0t] TIMEOUT: did not complete checks in time", $time);
    $finish;
  end

endmodule
