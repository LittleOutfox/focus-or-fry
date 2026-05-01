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

  //Output sequence of attention numbers
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

  localparam [3:0] IDLE = 4'd0,  START_CHECK = 4'd1, SEQUENCE_PULSE = 4'd2, SEQUENCE_READ = 4'd3, ATTENTION_PULSE = 4'd4, ATTENTION_READ = 4'd5, CHECKSUM_PULSE  = 4'd6, CHECKSUM_READ  = 4'd7, FINALIZATION = 4'd8;

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
          next_state = START_CHECK;
        end
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
          next_state = SEQUENCE_READ;
        end
      end

      SEQUENCE_READ: begin
        next_state = ATTENTION_PULSE;
      end

      ATTENTION_PULSE: begin
        if (!rx_empty) begin
          next_state = ATTENTION_READ;
        end
      end

      ATTENTION_READ: begin
        next_state = CHECKSUM_PULSE;
      end

      CHECKSUM_PULSE: begin
        if (!rx_empty) begin
          next_state = CHECKSUM_READ;
        end
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
        // IDLE and START_CHECK are not one state so you pulse read_uart one clock cycle
        IDLE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        START_CHECK: begin
          read_uart <= 0;
        end

        SEQUENCE_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        SEQUENCE_READ: begin
          read_uart   <= 0;
          sequencenum <= data;
        end

        ATTENTION_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        ATTENTION_READ: begin
          read_uart <= 0;
          attentionval <= data;
        end

        CHECKSUM_PULSE: begin
          if (!rx_empty) begin
            read_uart <= 1;
          end
        end

        CHECKSUM_READ: begin
          read_uart <= 0;
          checksum  <= data;
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
