module packet_rx #(
    parameter integer WIDTH = 8,
    parameter integer FIFO_DEPTH = 64
) (
    //module basics
    input wire clk,
    input wire reset,

    //data from UART core control
    output reg read_uart,  //the "pop" signal for FIFO
    input wire [WIDTH - 1:0] data,
    input wire rx_empty,

    //outwards interface
    input wire deq,
    output wire full,
    output wire empty,
    output wire [WIDTH - 1:0] attention,
    output reg error
);

  FIFO #(
      .WIDTH(WIDTH),
      .DEPTH(FIFO_DEPTH)
  ) output_fifo (
      .clk(clk),
      .reset(reset),
      .enq(write_flag),  //internal only
      .din(din),  //internal only
      .deq(deq),
      .full(FIFOfull),
      .dout(attention),
      .empty(empty)
  );

  localparam [3:0] IDLE             = 4'd0,
                   START_PULSE      = 4'd1,
                   START_WAIT       = 4'd2,
                   START_CHECK      = 4'd3,
                   SEQUENCE_PULSE   = 4'd4,
                   SEQUENCE_WAIT    = 4'd5,
                   SEQUENCE_READ    = 4'd6,
                   ATTENTION_PULSE  = 4'd7,
                   ATTENTION_WAIT   = 4'd8,
                   ATTENTION_READ   = 4'd9,
                   CHECKSUM_PULSE   = 4'd10,
                   CHECKSUM_WAIT    = 4'd11,
                   CHECKSUM_READ    = 4'd12,
                   FINALIZATION     = 4'd13;

  reg [3:0] state = IDLE;
  reg [3:0] next_state = 0;
  reg [WIDTH-1:0] sequencenum;
  reg [WIDTH-1:0] attentionval;
  reg [WIDTH-1:0] checksum;

  //FIFO control signals
  reg write_flag = 0;
  reg [WIDTH - 1:0] din;
  wire FIFOfull;
  assign full = FIFOfull;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Combinational logic for next state
  always @(*) begin
    next_state = state;
    case (state)
      IDLE: begin
        if (!rx_empty) begin
          next_state = START_PULSE;
        end
      end

      START_PULSE: begin
        if (!rx_empty) begin
          next_state = START_WAIT;
        end
      end

      START_WAIT: begin
        next_state = START_CHECK;
      end

      START_CHECK: begin
        if (data == 8'hAA) begin  //AA is our validation byte
          next_state = SEQUENCE_PULSE;
        end else begin
          next_state = IDLE;
        end
      end

      SEQUENCE_PULSE: begin
        if (!rx_empty) begin
          next_state = SEQUENCE_WAIT;
        end
      end

      SEQUENCE_WAIT: begin
        next_state = SEQUENCE_READ;
      end

      SEQUENCE_READ: begin
        next_state = ATTENTION_PULSE;
      end

      ATTENTION_PULSE: begin
        if (!rx_empty) begin
          next_state = ATTENTION_WAIT;
        end
      end

      ATTENTION_WAIT: begin
        next_state = ATTENTION_READ;
      end

      ATTENTION_READ: begin
        next_state = CHECKSUM_PULSE;
      end

      CHECKSUM_PULSE: begin
        if (!rx_empty) begin
          next_state = CHECKSUM_WAIT;
        end
      end

      CHECKSUM_WAIT: begin
        next_state = CHECKSUM_READ;
      end

      CHECKSUM_READ: begin
        next_state = FINALIZATION;
      end

      FINALIZATION: begin
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  //Output logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      error <= 0;
      write_flag <= 0;
      read_uart <= 0;
      sequencenum <= 0;
      attentionval <= 0;
      checksum <= 0;
      din <= 0;
    end else begin
      error <= 0;
      write_flag <= 0;
      read_uart <= 0;
      case (state)
        IDLE: begin
          // wait for upstream data; pop happens in START_PULSE
        end

        START_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        START_WAIT: begin
          read_uart <= 0;
        end

        START_CHECK: begin
          // data is now valid; next-state logic decides accept/reject
        end

        SEQUENCE_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        SEQUENCE_WAIT: begin
          read_uart <= 0;
        end

        SEQUENCE_READ: begin
          sequencenum <= data;
        end

        ATTENTION_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        ATTENTION_WAIT: begin
          read_uart <= 0;
        end

        ATTENTION_READ: begin
          attentionval <= data;
        end

        CHECKSUM_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        CHECKSUM_WAIT: begin
          read_uart <= 0;
        end

        CHECKSUM_READ: begin
          checksum <= data;
        end

        FINALIZATION: begin
          // computing checksum of our own compare against received checksum
          if (((8'hAA ^ sequencenum ^ attentionval) == checksum) && !FIFOfull) begin
            //enqueue the attention value into FIFO output
            write_flag <= 1;
            din <= attentionval;
          end else begin
            error <= 1;
          end
        end
      endcase
    end
  end

endmodule
