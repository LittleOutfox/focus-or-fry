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
  localparam [2:0] IDLE = 3'b000, START = 3'b001, DATA = 3'b010, STOP_BIT = 3'b011, STOP = 3'b100;
  reg [2:0] state = IDLE;
  reg [2:0] next_state = 0; // NOTE: next_state is closer to a wire. it's only "reg" beacuse you're driving from a procedural block
  reg [$clog2(FRAME_BITS) - 1:0] bit_index = 0;
  reg [$clog2(OVERSAMPLE) - 1:0] sample_index = 0;
  reg [FRAME_BITS - 1:0] tx_latch = 0;
  reg latch_next = 0; //used to wait one clk cycle

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
          next_state = STOP_BIT;
        end else begin
          next_state = state;
        end
      end

      STOP_BIT: begin
        if (baud_tick) begin
          if (sample_index == OVERSAMPLE - 1) begin
            next_state = STOP;
          end
        end else begin
          next_state = state;
        end
      end

      STOP: begin //purpose of STOP state is to have atleast one pulse of "ready" on tx_status
        next_state = IDLE;
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
            tx_status <= 1;
            latch_next <= 1'b1;   // arm latch for next cycle
          end
        end

        START: begin
          if (latch_next == 1'b1) begin
            tx_latch   <= tx_input; 
            latch_next <= 0;   // reset latch
          end
          
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

        STOP_BIT: begin
          tx_out <= 1;
          if (baud_tick) begin
            if (sample_index < OVERSAMPLE - 1) begin
              sample_index <= sample_index + 1;
            end else begin
              sample_index <= 0;
            end
          end
        end

        STOP: begin
          tx_status <= 0;
        end
      endcase
    end
  end

endmodule
