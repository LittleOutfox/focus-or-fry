module uart_tx (
    input clk,
    input start,
    input baud_tick,
    input reset,
    input [FRAME_BITS - 1:0] data,
    output reg tx_out,
    output reg tx_status //high = busy, low = ready
);
  parameter integer FRAME_BITS = 8;
  parameter integer OVERSAMPLE = 16;
  localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
  reg [1:0] state;
  reg [1:0] next_state = 0;
  reg [$clog2(FRAME_BITS) - 1:0] bit_index = 0;
  reg [$clog2(OVERSAMPLE) - 1:0] sample_index = 0;

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
      IDLE : begin
        if (start) begin
          next_state = START;
        end else begin
          next_state = IDLE;
        end
      end

      START : begin
        if (baud_tick) begin
          if (sample_index < OVERSAMPLE) begin
            sample_index = sample_index + 1;
          end else begin
            sample_index = 0;
            next_state = DATA;
          end
        end else begin
          sample_index = sample_index;
          next_state = state;
        end
      end

      DATA : begin
        if (baud_tick) begin
          if (sample_index < OVERSAMPLE) begin // KEEP TRANSMITTING SAME BIT
            sample_index = sample_index + 1;
          end else begin // TIME TO MOVE TO NEXT BIT
            sample_index = 0;
            if (bit_index <  FRAME_BITS) begin 
              bit_index = bit_index + 1;
            end else begin
              bit_index = 0;
              next_state = STOP;
            end
          end
        end else begin
          sample_index = sample_index;
          bit_index = bit_index;
          next_state = state;
        end
      end

      STOP : begin
        if (baud_tick) begin
          if (sample_index < OVERSAMPLE) begin
            sample_index = sample_index + 1;
          end else begin
            sample_index = 0;
            next_state = DATA;
          end
        end else begin
          sample_index = sample_index;
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
    end else begin
      case (state)
        IDLE : tx_out <= 1;
        START :tx_out <= 0;
        DATA : tx_out <= data[bit_index];
        STOP : tx_out <= 1;
      endcase
    end
  end

endmodule
