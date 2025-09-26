module FIFO (
    input clk,
    input reset,
    input enq, //flag for data into FIFO
    input [7:0] din, //data coming into FIFO
    input deq, //dequeue drop one byte out of FIFO
    output full, //queue is full don't write
    output [7:0] dout,
    output empty
);
    parameter integer WIDTH = 8;
    parameter integer DEPTH = 64; //MUST BE POWER OF TWO SO POINTER AUTO WRAP WORKS
    localparam integer AW = $clog2(DEPTH);

    //circular buffer means write in a circle not shifting list like C++
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wp = 0;  // write pointer
    reg [AW-1:0] rp = 0;  // read pointer
    reg [AW:0] count = 0; // 0..DEPTH
endmodule