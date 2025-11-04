module uart_tx #(
    parameter integer FRAME_BITS = 8,
    parameter integer OVERSAMPLE = 16
) (
    input clk,
    input start,
    input baud_tick,
    input reset,
    input [FRAME_BITS - 1:0] tx_input,
    output reg tx_out,
    output reg tx_status  //high = busy, low = ready
);
  localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
  reg [1:0] state = IDLE;
  reg [1:0] next_state = 0; // NOTE: next_state is closer to a wire. it's only "reg" beacuse you're driving from a procedural block
  reg [$clog2(FRAME_BITS) - 1:0] bit_index = 0;
  reg [$clog2(OVERSAMPLE) - 1:0] sample_index = 0;
  reg [FRAME_BITS - 1:0] tx_latch = 0;

  // Async reset w/ transition logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Combinational Logic for Next State
  always @(*) begin
    next_state = state;
    case (state)
      IDLE: begin
        if (start) begin
          next_state = START;
        end else begin
          next_state = IDLE;
        end
      end

      START: begin
        if (baud_tick && (sample_index == OVERSAMPLE - 1)) begin
          next_state = DATA;
        end else begin
          next_state = state;
        end
      end

      DATA: begin
        if (baud_tick && (sample_index == OVERSAMPLE - 1) && (bit_index == FRAME_BITS - 1)) begin
          next_state = STOP;
        end else begin
          next_state = state;
        end
      end

      STOP: begin
        if (baud_tick) begin
          if (sample_index == OVERSAMPLE - 1) begin
            next_state = IDLE;
          end
        end else begin
          next_state = state;
        end
      end

      default: next_state = state;
    endcase
  end

  // Synchronous Output Logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_out <= 1;
      tx_status <= 0;
      bit_index <= 0;
      sample_index <= 0;
      tx_latch <= 0;
    end else begin
      tx_status <= 1;
      case (state)
        IDLE: begin
          tx_out <= 1;
          tx_status <= 0;
          bit_index <= 0;
          sample_index <= 0;

          if (start) begin
            tx_latch <= tx_input;
          end
        end

        START: begin
          tx_out <= 0;
          if (baud_tick) begin
            if (sample_index < OVERSAMPLE - 1) begin
              sample_index <= sample_index + 1;
            end else begin
              sample_index <= 0;
            end
          end
        end

        DATA: begin
          tx_out <= tx_latch[bit_index];
          if (baud_tick) begin
            if (sample_index < OVERSAMPLE - 1) begin  // KEEP TRANSMITTING SAME BIT
              sample_index <= sample_index + 1;
            end else begin  // TIME TO MOVE TO NEXT BIT
              sample_index <= 0;
              if (bit_index < FRAME_BITS - 1) begin
                bit_index <= bit_index + 1;
              end else begin
                bit_index <= 0;
              end
            end
          end
        end

        STOP: begin
          tx_out <= 1;
          if (baud_tick) begin
            if (sample_index < OVERSAMPLE - 1) begin
              sample_index <= sample_index + 1;
            end else begin
              sample_index <= 0;
            end
          end
        end
      endcase
    end
  end

endmodule
