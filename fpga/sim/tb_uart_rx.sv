`timescale 1ns / 1ps

module tb_uart_rx ();

  localparam int CLK_HZ = 100_000_000;  // 100 MHz
  localparam int BAUD = 115200;
  localparam int CLK_NS = 10;  // 100 MHz => 10 ns
  localparam int BIT_NS = 1_000_000_000 / BAUD;  // ~8680 ns
  localparam int TICKS_PER_BIT = BIT_NS / CLK_NS;  // ~868 clk edges
  localparam int HALF_BIT_TCK = TICKS_PER_BIT / 2;

  // DUT I/O
  logic       clk;
  logic       reset;
  logic       rx_sync_in;
  logic       center_tick;
  logic [7:0] rx_data;
  logic       frame_error;
  logic       valid;
  logic       phase_arm;  //unused

  // Scratch
  int         k;
  byte        exp;

  uart_rx dut (
      .clk        (clk),
      .rx_sync_in (rx_sync_in),
      .center_tick(center_tick),
      .reset      (reset),
      .rx_data    (rx_data),
      .frame_error(frame_error),
      .valid      (valid),
      .phase_arm  (phase_arm)
  );

  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  initial begin
    $dumpfile("dump.vcd");  // name of the VCD file to generate
    $dumpvars(0, tb_uart_rx);  // dump all signals in testbench 'tb' hierarchy
  end


  task automatic wait_clocks(input int n);
    begin
      for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
  endtask

  // Make a one-cycle center_tick at the middle of a bit period
  task automatic center_of_bit();
    begin
      wait_clocks(HALF_BIT_TCK);
      center_tick <= 1'b1;
      @(posedge clk);
      center_tick <= 1'b0;
      @(posedge clk); //advances on centre tick, no need to wait till end of bit
    end
  endtask

  // Send one 8N1 frame (LSB-first). If bad_stop=1, the stop bit is held low.
  task automatic send_byte(input byte b, input bit bad_stop);
    int i;
    begin
      rx_sync_in <= 1'b0;
      center_of_bit();

      // data bits LSB-first
      for (i = 0; i < 8; i = i + 1) begin
        rx_sync_in <= b[i];
        center_of_bit();
      end

      // stop bit = 1 normally (or 0 for bad stop)
      rx_sync_in <= (bad_stop ? 1'b0 : 1'b1);
      center_of_bit();
    end
  endtask

  initial begin
    // init
    rx_sync_in  = 1'b1;  // idle high
    center_tick = 1'b0;
    reset       = 1'b1;
    wait_clocks(5);
    reset = 1'b0;
    wait_clocks(5);

    // --- Test 1: Good frame 0x55 ---
    exp = 8'h55;
    $display("[%0t] TEST1: send 0x%0h (good frame)", $time, exp);
    send_byte(exp,  /*bad_stop*/ 1'b0);

    if (!valid) $fatal(1, "[%0t] TEST1: expected valid=1", $time);
    if (frame_error) $fatal(1, "[%0t] TEST1: expected frame_error=0", $time);
    if (rx_data !== exp)
      $fatal(1, "[%0t] TEST1: data mismatch got=0x%0h exp=0x%0h", $time, rx_data, exp);
    $display("[%0t] TEST1: PASS (rx=0x%0h)", $time, rx_data);

    // --- Test 2: Framing error (bad stop) ---
    exp = 8'hC1;
    $display("[%0t] TEST2: send 0x%0h with bad stop", $time, exp);
    send_byte(exp,  /*bad_stop*/ 1'b1);

    if (!frame_error) $fatal(1, "[%0t] TEST2: expected frame_error=1", $time);
    $display("[%0t] TEST2: PASS (frame_error=1)", $time);

    $display("[%0t] ALL DONE :)", $time);
    $finish;
  end

endmodule
