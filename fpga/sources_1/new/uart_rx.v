module uart_rx (
    input clk,
    input rx_sync_in,
    input center_tick,
    input reset, //active-high
    output reg [FRAME_BITS - 1:0] rx_data,
    output reg frame_error, 
    output reg valid
);

    parameter integer FRAME_BITS = 8;
    localparam [1:0]
        IDLE = 2'd0,
        START_CHECK = 2'd1,
        DATA = 2'd2,
        STOP_CHECK = 2'd3;

    reg [1:0] state = IDLE;
    reg [1:0] next_state = 0;
    reg [$clog2(FRAME_BITS) - 1: 0] bit_index = 0;

    // Async reset w/ transition logic
    always@(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Combinational Logic for Next State
    always@(*) begin
        next_state = state;
        case (state)
            IDLE : begin
                if(!rx_sync_in) begin
                    next_state = START_CHECK;
                end
            end
            START_CHECK : begin
                if(center_tick && !rx_sync_in) begin
                    next_state = DATA;
                end else if (center_tick) begin
                    next_state = IDLE;
                end
            end

            DATA : begin
                if(center_tick && bit_index == FRAME_BITS - 1) begin
                    next_state = STOP_CHECK;
                end
            end

            STOP_CHECK : begin
                if(center_tick) begin
                    next_state = IDLE; //Transition to IDLE regardless of errors
                end
            end

            default : next_state = IDLE;
        endcase
    end

    //Output logic
    always@(posedge clk or posedge reset) begin
        if(reset) begin
            rx_data <= 0;
            bit_index <= 0;
            valid <= 0;
            frame_error <= 0;
        end else begin
            valid <= 0;
            case (state)
                IDLE : begin
                    // Just for safety
                    frame_error <= 0;
                    bit_index <= 0;
                end
                DATA : begin
                    if(center_tick && bit_index != FRAME_BITS - 1) begin
                        rx_data[bit_index] <= rx_sync_in;
                        bit_index <= bit_index + 1;
                    end else if(center_tick && bit_index == FRAME_BITS - 1) begin
                        rx_data[bit_index] <= rx_sync_in;
                        bit_index <= 0;
                    end
                end

                STOP_CHECK : begin
                    if(center_tick && rx_sync_in) begin
                        valid <= 1;
                        frame_error <= 0;
                    end else if (center_tick) begin
                        frame_error <= 1;
                    end
                end
            endcase
        end
    end
endmodule
