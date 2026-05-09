module focus_detector #(
    parameter integer WIDTH = 8,
    parameter integer THRESHOLD = 60,
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer COOLDOWN_TICKS = CLOCK_HZ * 5,
    parameter integer BAD_LIMIT = 3
) (
    input wire clk,
    input wire reset,

    //interfacing with rolling_avg module
    input wire read_average,
    input wire [WIDTH - 1:0] avg_val,

    // from STM32
    input wire acknowledge,

    //outwards facing interface
    output reg focused
);

  localparam [1:0] READ = 2'd0, TRIGGER = 2'd1, FOCUSED = 2'd2, COOLDOWN = 2'd3;
  localparam COUNTERWIDTH = $clog2(
      COOLDOWN_TICKS + 1
  );  // bits required for a counter for 5 seconds

  reg [1:0] count = 0;
  reg [1:0] state = READ;
  reg [1:0] next_state = 0;
  reg [COUNTERWIDTH - 1:0] timer = 0;
  wire ack_sync;

  sync_2ff u_rx_sync (
      .async_in(acknowledge),
      .clk(clk),
      .synced_input(ack_sync)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= READ;
    end else begin
      state <= next_state;
    end
  end

  // combinational logic for next state
  always @(*) begin
    next_state = state;
    case (state)
      READ: begin
        if (read_average) begin
          if (avg_val >= THRESHOLD) begin
            next_state = FOCUSED;
          end else begin
            if (count + 1 >= BAD_LIMIT) begin
              next_state = TRIGGER;
            end else begin
              next_state = READ;
            end
          end
        end
      end

      FOCUSED: begin
        next_state = READ;
      end

      TRIGGER: begin
        // handshake: hold focus low until acknowledged by STM32
        if (ack_sync) begin
          next_state = COOLDOWN;
        end else begin
          next_state = TRIGGER;
        end
      end

      COOLDOWN: begin
        if (timer + 1 >= COOLDOWN_TICKS) begin
          next_state = READ;
        end else begin
          next_state = COOLDOWN;
        end
      end

      default: next_state = READ;
    endcase
  end

  //output logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      count   <= 0;
      focused <= 1;
      timer   <= 0;
    end else begin
      // the FSM assumes that the poll rate of the mind EKG is much slower than the sampling rate of this FSM/FPGA clk speed
      case (state)
        READ: begin
          focused <= 1;
          if (read_average) begin
            if (avg_val >= THRESHOLD) begin
              count <= 0;
            end else begin
              if (count + 1 >= BAD_LIMIT) begin
                count <= 0;
              end else begin
                count <= count + 1;
              end
            end
          end
        end

        FOCUSED: begin
          count   <= 0;
          focused <= 1;
        end

        TRIGGER: begin
          count   <= 0;
          focused <= 0;
        end

        COOLDOWN: begin
          count   <= 0;
          focused <= 1;

          if (timer + 1 >= COOLDOWN_TICKS) begin
            timer <= 0;
          end else begin
            timer <= timer + 1;
          end
        end
      endcase
    end
  end
endmodule
