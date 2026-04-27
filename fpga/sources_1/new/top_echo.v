`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/02/2025 01:04:48 AM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module top (
    input  wire clk,         // 100 MHz board clock
    input  wire reset_btn,   // active-high reset (map to a pushbutton)

    input  wire uart_rx,     // from USB-UART / FTDI
    output wire uart_tx,     // to USB-UART / FTDI

    output wire [3:0] leds   // simple debug
);

    // UART core <-> top interface
    wire [7:0] rx_data;
    wire       rx_empty;
    wire       rx_full;

    wire       tx_full;
    wire       rx_frame_error;

    reg  [7:0] rx_latched;
    reg        read_uart;
    reg        write_uart;

    // Instantiate your UART core with default parameters
    uart_core #(
        .WIDTH(8),
        .CLOCK_HZ(100_000_000),
        .BAUD(115_200)
        // OVERSAMPLE, FIFO depths use defaults
    ) u_uart_core (
        .clk(clk),
        .rx(uart_rx),
        .tx(uart_tx),

        .reset(reset_btn),

        .read_uart(read_uart),
        .read_data(rx_data),
        .rx_empty(rx_empty),
        .rx_full(rx_full),

        .write_data(rx_latched),
        .write_uart(write_uart),
        .tx_full(tx_full),
        .rx_frame_error(rx_frame_error)
    );

    // Simple RX->TX echo FSM
    localparam S_IDLE  = 2'd0;
    localparam S_READ  = 2'd1;
    localparam S_LATCH = 2'd2;
    localparam S_WRITE = 2'd3;

    reg [1:0]state;

    always @(posedge clk or posedge reset_btn) begin
        if (reset_btn) begin
            state       <= S_IDLE;
            read_uart   <= 1'b0;
            write_uart  <= 1'b0;
            rx_latched  <= 8'h00;
        end else begin
            // default: no FIFO operations
            read_uart   <= 1'b0;
            write_uart  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (!rx_empty && !tx_full) begin
                        // Ask RX FIFO to pop one byte on the transition;
                        // S_READ is a one-cycle wait so dout updates before we sample it.
                        read_uart <= 1'b1;
                        state     <= S_READ;
                    end
                end

                S_READ: begin
                    state <= S_LATCH;
                end

                S_LATCH: begin
                    // Now RX FIFO output is stable, so capture it
                    rx_latched <= rx_data;
                    state      <= S_WRITE;
                end

                S_WRITE: begin
                    // Now rx_latched is stable, so write it to TX FIFO
                    write_uart <= 1'b1;
                    state      <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // Debug LEDs
    assign leds[0] = ~rx_empty;        // RX has data
    assign leds[1] = tx_full;          // TX FIFO full
    assign leds[2] = rx_full;          // RX FIFO full
    assign leds[3] = rx_frame_error;   // framing error seen

endmodule
