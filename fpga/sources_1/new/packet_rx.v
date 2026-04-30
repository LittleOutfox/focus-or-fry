module packet_rx #(
    parameter integer WIDTH = 8,
    parameter integer FIFO_DEPTH = 64
) (
    //module basics
    input wire clk,
    input wire reset,

    //data from UART core control
    output wire read_uart,  //the "pop" signal for FIFO
    input wire [WIDTH - 1:0] data,
    input wire rx_empty,
    input wire rx_full
);

  //Output sequence of attention numbers
  FIFO #(
      .WIDTH(WIDTH),
      .DEPTH(FIFO_DEPTH)
  ) attention_fifo (
      .clk  (clk),
      .reset(reset),
      .enq  (write_uart),
      .din  (write_data),
      .deq  (~tx_status),
      .full (tx_full),
      .dout (tx_data_in),
      .empty(tx_start)
  );

  localparam [3:0] IDLE = 4'd0,  START_CHECK = 4'd1, SEQUENCE_PULSE = 4'd2, SEQUENCE_READ = 4'd3, ATTENTION_PULSE = 4'd4, ATTENTION_READ = 4'd5, CHECKSUM_PULSE  = 4'd6, CHECKSUM_READ  = 4'd7, FINALIZATION = 4'd8;

  reg [3:0] state = START_CHECK;
  reg [3:0] next_state = 0;
  reg [7:0] sequencenum = 0;
  reg [7:0] attentionval = 0;
  reg [7:0] checksum = 0;


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
        if (!rx_empty == 1) begin
          next_state = START_CHECK;
        end
      end

      START_CHECK: begin
        if (data == 8'hAA) begin  //AA is our validation byte
          next_state = SEQUENCE_PULSE;
        end
      end

      // And so on so forth...
    endcase
  end

  //Output logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin

    end else begin
      case (state)
        // IDLE and START_CHECK are not one state so you pulse read_uart one clock cycle
        IDLE: begin
          if (!rx_empty == 1) begin
            read_uart <= 1;
          end
        end

        START_CHECK: begin
          read_uart <= 0;
        end

        // And so on so forth...
      endcase
    end
  end

endmodule
