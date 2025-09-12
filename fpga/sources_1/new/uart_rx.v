module uart_rx (
    input clk,
    input rx_sync_in,
    input center_tick,
    input reset, //active-high
    output reg [7:0] rx_data,
    output reg frame_error, 
    output reg valid
);

    parameter integer FRAME_BITS = 8;
    localparam [2:0]
        IDLE = 3'd0,
        START_CHECK = 3'd1,
        DATA = 3'd2,
        STOP_CHECK = 3'd3,
        DONE = 3'd4;

    reg [2:0] state = IDLE;
    reg [2:0] bit_index = 0;
    reg [2:0] next_state = 0;

    // Async reset w/ transition logic
    always@(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin 
            state <= next_state;
        end
    end
endmodule