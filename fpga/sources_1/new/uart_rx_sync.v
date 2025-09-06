module uart_rx_synchronizer (
    input  async_in,
    input  clk,
    output synced_input
);
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)reg filter1 = 1'b1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)reg filter2 = 1'b1;


  always @(posedge clk) begin
    filter1 <= async_in;
    filter2 <= filter1;
  end

  assign synced_input = filter2;
endmodule
