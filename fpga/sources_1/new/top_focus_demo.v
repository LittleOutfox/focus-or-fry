module top_focus_demo #(
    // real-hardware defaults; the testbench overrides the slow ones
    parameter integer CLOCK_HZ       = 100_000_000,
    parameter integer BAUD           = 115_200,
    parameter integer THRESHOLD      = 60,
    parameter integer BAD_LIMIT      = 2,
    parameter integer COOLDOWN_TICKS = CLOCK_HZ * 5,   // 5 s on the board
    parameter integer ROLL_DEPTH     = 4,              // must be a power of two
    parameter integer HB_BIT         = 25,             // heartbeat = bit HB_BIT of free-run cnt
    parameter integer STRETCH_TICKS  = 25_000_000      // ~0.25 s LED stretch on the board
) (
    input  wire       clk,        // 100 MHz Basys 3 clock
    input  wire       reset_btn,  // active-high reset button
    input  wire       ack_btn,    // acknowledge button for focus_detector
    input  wire       uart_rx,    // UART RX from STM32
    output wire       uart_tx,    // UART TX (unused for now, but wired through uart_core)
    output wire [7:0] leds        // debug LEDs
);

  wire [7:0] rx_data;
  wire       rx_empty;
  wire       rx_full;
  wire       rx_frame_error;
  wire       tx_full;  // unused for now
  wire       read_uart;  // driven ONLY by rolling_avg.read_attention

  // rolling_avg -> focus_detector
  wire [7:0] avg_val;
  wire       data_valid;

  // focus_detector output
  wire       focused;
  wire       focus_lost = ~focused;

  uart_core #(
      .WIDTH(8),
      .CLOCK_HZ(CLOCK_HZ),
      .BAUD(BAUD)
  ) u_uart_core (
      .clk  (clk),
      .reset(reset_btn),

      .rx(uart_rx),
      .tx(uart_tx),

      // RX side: rolling_avg pulls bytes out of the RX FIFO
      .read_uart(read_uart),
      .read_data(rx_data),
      .rx_empty(rx_empty),
      .rx_full(rx_full),
      .rx_frame_error(rx_frame_error),

      // TX side: not used yet, just hold inputs idle
      .write_uart(1'b0),
      .write_data(8'h00),
      .tx_full(tx_full)
  );

  rolling_avg #(
      .WIDTH(8),
      .DEPTH(ROLL_DEPTH)
  ) u_rolling_avg (
      .clk  (clk),
      .reset(reset_btn),

      // pulls bytes from uart_core RX FIFO
      .read_attention(read_uart),
      .empty(rx_empty),
      .attention(rx_data),

      // outputs to focus_detector
      .data_valid(data_valid),
      .avg_val(avg_val)
  );

  focus_detector #(
      .WIDTH(8),
      .THRESHOLD(THRESHOLD),
      .CLOCK_HZ(CLOCK_HZ),
      .COOLDOWN_TICKS(COOLDOWN_TICKS),
      .BAD_LIMIT(BAD_LIMIT)
  ) u_focus_detector (
      .clk  (clk),
      .reset(reset_btn),

      .read_average(data_valid),
      .avg_val(avg_val),

      .acknowledge(ack_btn),

      .focused(focused)
  );

  // heartbeat counter is HB_BIT+1 bits wide so heartbeat = top bit
  reg [HB_BIT:0] hb_cnt = 0;
  always @(posedge clk or posedge reset_btn) begin
    if (reset_btn) hb_cnt <= 0;
    else hb_cnt <= hb_cnt + 1;
  end
  wire heartbeat = hb_cnt[HB_BIT];

  // pulse stretcher; counter is just wide enough to hold STRETCH_TICKS
  localparam integer STRETCH_W = $clog2(STRETCH_TICKS + 1);
  reg [STRETCH_W-1:0] dv_stretch_cnt = 0;
  reg                 dv_stretch_led = 0;
  always @(posedge clk or posedge reset_btn) begin
    if (reset_btn) begin
      dv_stretch_cnt <= 0;
      dv_stretch_led <= 0;
    end else if (data_valid) begin
      // restart the stretch window every time data_valid pulses
      dv_stretch_cnt <= STRETCH_TICKS[STRETCH_W-1:0];
      dv_stretch_led <= 1'b1;
    end else if (dv_stretch_cnt != 0) begin
      dv_stretch_cnt <= dv_stretch_cnt - 1;
    end else begin
      dv_stretch_led <= 1'b0;
    end
  end

  // ------------------------------------------------------------
  // Debug LEDs
  // ------------------------------------------------------------
  assign leds[0] = heartbeat;  // FPGA is alive
  assign leds[1] = ~rx_empty;  // RX FIFO has data
  assign leds[2] = rx_full;  // RX FIFO full
  assign leds[3] = rx_frame_error;  // UART framing error
  assign leds[4] = dv_stretch_led;  // rolling_avg pulsed (stretched)
  assign leds[5] = focused;  // currently focused
  assign leds[6] = focus_lost;  // focus-loss request active
  assign leds[7] = ack_btn;  // raw ack button state

endmodule
