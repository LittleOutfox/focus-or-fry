module uart_core # (
    parameter integer WIDTH = 8
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD = 115_200,
    parameter integer OVERSAMPLE = 16,
    parameter integer TX_FIFO_DEPTH = 16,
    parameter integer RX_FIFO_DEPTH = 16,
) (
    // outwards interfacing ports
    input wire clk,
    input wire rx,
    output wire tx,

    // internal interface ports
    input wire read_uart, //the "pop" signal for FIFO
    output wire [WIDTH - 1:0] read_data,
    output wire rx_empty,

    input wire [WIDTH - 1:0] write_data,
    input wire write_uart,
    output wire tx_full
);

    wire baud_tick;

    baud_generator # (
        .CLOCK_HZ   (CLOCK_HZ),
        .BAUD (BAUD)
        .OVERSAMPLE(OVERSAMPLE)
    ) u_baud_gen (
        .clk(clk),
        .enable(baud_tick)
    )

    FIFO # (
        
    ) tx_fifo (

    )
endmodule