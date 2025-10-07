`timescale 1ns/1ps   // sets time unit / precision

module tb_FIFO (); 
    parameter integer WIDTH = 8;

    // test signals
    reg clk;
    reg reset;
    reg enq; //flag for data into FIFO
    reg [WIDTH - 1:0] din; //data coming into FIFO
    reg deq; //dequeue drop one byte out of FIFO
    wire full; //queue is full don't write
    wire [WIDTH - 1:0] dout;
    wire empty;

    //instantiate DUT
    FIFO dut(
        .clk(clk),
        .reset(reset),
        .enq(enq), //flag for data into FIFO
        .din(din), //data coming into FIFO
        .deq(deq), //dequeue drop one byte out of FIFO
        .full(full), //queue is full don't write
        .dout(dout),
        .empty(empty)
    );

    //creating the clock
    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    //end the simulation
    initial begin
        #2000;
        $display("[%0t] TIMEOUT - finishing", $time);
        $finish;
    end
endmodule