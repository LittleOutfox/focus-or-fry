module baud_generator #(
  parameter integer CLOCK_HZ = 100_000_000,
  parameter integer BAUD = 115_200,
  parameter integer OVERSAMPLE = 16,
  parameter integer DIV = CLOCK_HZ / (OVERSAMPLE * BAUD),
  parameter integer COUNTER_BITS = $clog2(DIV)  // How large register needs to be to store the bits of DIV
) (
    input clk,
    output reg enable = 0
);
  reg [COUNTER_BITS - 1:0] counter = 0;

  always @(posedge clk) begin
    if (counter == DIV - 1) begin
      counter <= 0;
      enable  <= 1;
    end else begin
      counter <= counter + 1;
      enable  <= 0;
    end
  end

endmodule
