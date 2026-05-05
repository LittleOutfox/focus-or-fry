module rolling_avg #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 8 //MUST BE POWER OF TWO SO POINTER AUTO WRAP WORKS (depth is # of bits to hold
) (
    input wire clk,
    input wire reset,
    output reg data_valid,  // pulses high when avg_val is updated
    output reg [WIDTH - 1:0] avg_val,

    // interfacing with packet_rx
    output reg read_attention,
    input wire empty,
    input wire [WIDTH - 1:0] attention
);

  localparam [1:0] IDLE = 2'd0, WAIT = 2'd1, READ = 2'd2, UPDATE = 2'd3;
  localparam integer SUM_WIDTH = WIDTH + AW;

  reg [1:0] state = IDLE;
  reg [1:0] next_state = 0;

  localparam integer AW = $clog2(DEPTH);
  //circular buffer means write in a circle not shifting list like C++
  reg [WIDTH-1:0] mem[0:DEPTH-1];
  reg [AW-1:0] wp = 0;  // write pointer
  reg [AW:0] count = 0;  // 0..DEPTH
  reg [SUM_WIDTH-1:0] sum = 0;
  reg [SUM_WIDTH-1:0] store = 0;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // combinational logic for next state
  always @(*) begin
    next_state = state;
    case (state)
      IDLE: begin
        if (!empty) begin
          next_state = WAIT;
        end else begin
          next_state = IDLE;
        end
      end

      WAIT: begin
        next_state = READ;
      end

      READ: begin
        next_state = UPDATE;
      end

      UPDATE: begin
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  // output logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      read_attention <= 0;
      count <= 0;
      sum <= 0;
      data_valid <= 0;
      avg_val <= 0;
      wp <= 0;
      store <= 0;
    end else begin
      read_attention <= 0;
      data_valid <= 0;
      case (state)
        IDLE: begin
          if (!empty) begin
            read_attention <= 1;
          end
        end

        WAIT: begin
          read_attention <= 0;
        end

        READ: begin
          if (count < DEPTH) begin
            count <= count + 1;
            sum   <= sum + attention;
          end else begin
            sum <= sum - mem[wp] + attention;
          end

          store <= attention;
        end

        UPDATE: begin
          mem[wp] <= store;
          if (count == DEPTH) begin
            data_valid <= 1;
            avg_val <= sum >> AW;
          end
          wp <= wp + 1;  // will autowrap back around
        end
      endcase
    end
  end

endmodule
