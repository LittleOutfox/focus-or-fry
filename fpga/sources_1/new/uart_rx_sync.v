module uart_rx_synchronizer (
    input async_in,
    input clk,
    output synced_input
);
    reg filter1 = 1;
    reg filter2 = 1;

    always@(posedge clk) begin 
        filter1 <= async_in;
        filter2 <= filter1;
    end

    assign synced_input = filter2;
endmodule