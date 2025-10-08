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

    //dump waveform file
    // put near the top-level of tb_FIFO
    initial begin
        $dumpfile("tb_fifo.vcd"); // output filename
        $dumpvars(0, tb_FIFO);    // dump whole tb hierarchy (depth 0 = all)
    end

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

    //automatic keyword allows multiple copies of function
    task automatic do_reset;
    begin
        reset = 1;
        enq = 0; 
        deq = 0; 
        din = '0; //fill bus with 0
        repeat (3) @(posedge clk); //wait 3 clock cycles
        reset = 0;
        @(posedge clk); //wait one more clock cycle
    end
    endtask

    task automatic enqueue(input [WIDTH-1:0] data);
    begin
        @(posedge clk);
        while (full) @(posedge clk); // wait until not full, then pulse enq for one cycle
        din <= data;
        enq <= 1;
        @(posedge clk);
        enq <= 0;
    end
    endtask

    task automatic dequeue(output [WIDTH-1:0] data_out);
    begin
        @(posedge clk);
        while (empty) @(posedge clk);
        deq <= 1;
        @(posedge clk);
        deq <= 0;
        data_out = dout;
    end
    endtask

    integer i;
    reg [WIDTH-1:0] got;
    reg [WIDTH-1:0] testvec [0:7];

    initial begin
        // test vectors
        testvec[0]=8'h11; testvec[1]=8'h22; testvec[2]=8'h33; testvec[3]=8'h44;
        testvec[4]=8'h55; testvec[5]=8'h66; testvec[6]=8'h77; testvec[7]=8'h88;

        // init
        enq = 0; deq = 0; din = '0; reset = 0;

        // reset DUT
        do_reset();

        // 1) enqueue four items
        for (i=0; i<4; i=i+1) begin
            enqueue(testvec[i]);
        end

        // Expect: empty==0
        if (empty) begin
            $error("[%0t] ERROR: FIFO reports empty after enqueues", $time);
            $finish;
        end

        // 2) dequeue the same four, check order (FIFO behavior)
        for (i=0; i<4; i=i+1) begin
            dequeue(got);
            if (got !== testvec[i]) begin
                $error("[%0t] MISMATCH: expected %0h, got %0h at i=%0d", $time, testvec[i], got, i);
                $finish;
            end else begin
                $display("[%0t] OK: got %0h", $time, got);
            end
        end

        // 3) Check empty flag asserted again
        @(posedge clk);
        if (!empty) $error("[%0t] ERROR: FIFO not empty after draining", $time);
        else        $display("[%0t] PASS: Basic enqueue/dequeue/flags", $time);

        $finish;
    end
endmodule
