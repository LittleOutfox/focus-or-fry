module FIFO #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 64 //MUST BE POWER OF TWO SO POINTER AUTO WRAP WORKS (depth is # of bits to hold
) (
    input clk,
    input reset,
    input enq, //flag for data into FIFO
    input [WIDTH - 1:0] din, //data coming into FIFO
    input deq, //dequeue drop one byte out of FIFO
    output full, //queue is full don't write
    output reg [WIDTH - 1:0] dout,
    output empty
);
    localparam integer AW = $clog2(DEPTH);
    //circular buffer means write in a circle not shifting list like C++
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wp = 0;  // write pointer
    reg [AW-1:0] rp = 0;  // read pointer
    reg [AW:0] count = 0; // 0..DEPTH

    //enqueue and dequeue flags
    wire valid_enq;
    wire valid_deq;

    assign valid_enq = enq && !full;
    assign valid_deq = deq && !empty;
    assign full = (count == DEPTH);
    assign empty = (count == 0);

    //NOTE: Apparently a good FIFO does not strobe the output but rather holds the output like a storage element
    always@(posedge clk or posedge reset) begin 
        if (reset) begin
            wp <= 0;
            rp <= 0;
            dout <= 0;
            count <= 0;
        end else begin
            if (valid_enq) begin
                mem[wp] <= din;
                wp <= wp + 1;
            end 
            if (valid_deq) begin
                dout <= mem[rp];
                rp <= 1 + rp;
            end
            count <= count + valid_enq - valid_deq;
        end
    end
endmodule