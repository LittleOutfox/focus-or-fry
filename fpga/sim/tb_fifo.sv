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
        #20000;
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
        @(posedge clk);
        data_out = dout;
    end
    endtask

    // a reference model model of a FIFO, essentially a vector from C++
    // NOTE: this is SystemVerilog ONLY
    logic [WIDTH-1:0] model_q[$];

    //enqueue overflow test, see if it ignores when full
    task automatic try_enqueue(input [WIDTH-1:0] data, output bit accepted);
    bit full_before;
    begin
        // use blocking = when doing TB stuff, use non blocking <= when driving DUT inputs
        @(posedge clk);
        full_before = full;
        din <= data;
        enq <= 1;
        @(posedge clk);
        enq <= 0;
        accepted = !full_before;      // registered-output FIFO samples on this edge
        if (accepted) model_q.push_back(data);
    end
    endtask

    //dequeue underflow test, pulse deq regardless of empty, report if accepted and return data
    task automatic try_dequeue(output [WIDTH-1:0] data_out, output bit accepted);
        bit empty_before;
        reg [WIDTH-1:0] expected;
        begin
            @(posedge clk);
            empty_before = empty;
            deq <= 1;
            @(posedge clk);
            deq <= 0;
            @(posedge clk);
            accepted = !empty_before; // registered-output FIFO presents data next cycle
            data_out  = dout;

            if (accepted) begin
                if (model_q.size() == 0) begin
                    $error("[%0t] REF MODEL underflow", $time);
                end else begin
                    expected = model_q[0];     // front element
                    model_q  = model_q[1:$];   // drop the first element
                    if (data_out !== expected) begin
                        $error("[%0t] MISMATCH (try_dequeue): expected %0h got %0h",
                            $time, expected, data_out);
                    end
                end
            end
        end
    endtask


    initial begin
        bit acc;
        reg [WIDTH-1:0] val;
        integer i;
        reg [WIDTH-1:0] got;
        reg [WIDTH-1:0] testvec [0:7];
        int iter;
        int pops;
        bit empty_b;
        bit full_b;

        // test vectors
        testvec[0]=8'h11; testvec[1]=8'h22; testvec[2]=8'h33; testvec[3]=8'h44;
        testvec[4]=8'h55; testvec[5]=8'h66; testvec[6]=8'h77; testvec[7]=8'h88;

        // init
        enq = 0; deq = 0; din = '0; reset = 0;

        // reset DUT
        do_reset();

        // enqueue four items
        for (i=0; i<4; i=i+1) begin
            enqueue(testvec[i]);
        end

        // expect: empty==0
        if (empty) begin
            $error("[%0t] ERROR: FIFO reports empty after enqueues", $time);
            $finish;
        end

        // dequeue the same four, check order (FIFO behavior)
        for (i=0; i<4; i=i+1) begin
            dequeue(got);
            if (got !== testvec[i]) begin
                $error("[%0t] MISMATCH: expected %0h, got %0h at i=%0d", $time, testvec[i], got, i);
                $finish;
            end else begin
                $display("[%0t] OK: got %0h", $time, got);
            end
        end

        // check empty flag asserted again
        @(posedge clk);
        if (!empty) $error("[%0t] ERROR: FIFO not empty after draining", $time);
        else $display("[%0t] PASS: Basic enqueue/dequeue/flags", $time);

        // clear model and DUT
        model_q.delete();
        do_reset();

        // fill FIFO
        $display("\n[EXT] 1) Fill to full");
        iter = 0;
        while (!full && iter < 1024) begin
            try_enqueue($urandom_range(0,255), acc);
            iter++;
        end

        if (!full) $error("[%0t] ERROR: full did not assert after many enqueues", $time);
        else $display("[%0t] PASS: full asserted after filling (%0d writes)", $time, model_q.size());

        // try one more enqueue; must be ignored
        try_enqueue(8'hA5, acc);
        if (acc) $error("[%0t] ERROR: enqueue accepted while full", $time);
        else $display("[%0t] PASS: extra enqueue ignored while full", $time);

        // dequeue to empty and beyond
        $display("\n[EXT] 2) Drain to empty");
        iter = 0;
        while (!empty && iter < 1024) begin
            try_dequeue(val, acc);
            if (!acc) $error("[%0t] ERROR: dequeue rejected while not empty", $time);
            iter++;
        end

        if (!empty) $error("[%0t] ERROR: empty did not assert after draining", $time);
        else $display("[%0t] PASS: empty asserted after draining", $time);

        // try one more dequeue, must be ignored, catches any dequeue beyond empty error
        try_dequeue(val, acc);
        if (acc) $error("[%0t] ERROR: dequeue accepted while empty", $time);
        else $display("[%0t] PASS: extra dequeue ignored while empty", $time);

        // wraparound pointers testing
        // fill, pop, and push a few, then drain, testing for order preservation
        $display("\n[EXT] 3) Wraparound pointers");

        // refill until full
        iter = 0;
        while (!full && iter < 1024) begin
            try_enqueue($urandom_range(0,255), acc);
            iter++;
        end
        if (!full) $error("[%0t] ERROR: failed to reach full for wrap test", $time); //filled with 1024 items and somehow still not full?

        // pop 3 (or until empty if shallow)
        pops = 0;
        for (pops = 0; pops < 3 && !empty; pops++) begin
            try_dequeue(val, acc);
        end

        // push 3 new values to force pointer wrap
        for (int k = 0; k < pops; k++) begin
            try_enqueue(8'hC0 + k, acc);
            if (!acc) $error("[%0t] ERROR: could not enqueue during wrap refill", $time);
        end

        // drain all and let try_dequeue compare against model_q
        iter = 0;
        while (!empty && iter < 1024) begin
            try_dequeue(val, acc);
            iter++;
        end
        if (model_q.size() != 0) $error("[%0t] ERROR: model not empty after drain", $time);
        else $display("[%0t] PASS: wraparound preserved order", $time);

        // enqueue + dequeue at the same time
        $display("\n[EXT] 4) Simultaneous enqueue+dequeue");

        // Prep: ensure not empty and not full
        // NOTE: you didn't design your FIFO to handle dual enq & deq at the same time on edges, likely rejects on edges
        do_reset();
        model_q.delete();

        // preload a mid-level depth (e.g., 4)
        for (int k = 0; k < 4; k++) begin
            try_enqueue(8'h30 + k, acc);
        end
        if (empty || full) $error("[%0t] ERROR: bad precondition for simultaneous test", $time); //pick a diferent mid-level depth

        // observe flags before
        empty_b = empty;
        full_b  = full;

        // do one cycle with both enq & deq
        @(posedge clk);
        din <= 8'hEE;
        enq <= 1;
        deq <= 1;
        @(posedge clk);
        enq <= 0;
        deq <= 0;

        // update reference model: pop front, push back
        void'(model_q.pop_front());
        model_q.push_back(8'hEE);

        // give registered-output a cycle to settle and check flags
        @(posedge clk);
        if (empty !== empty_b || full !== full_b) begin
            $error("[%0t] ERROR: flags changed on 1-in/1-out (empty %0b->%0b, full %0b->%0b)", $time, empty_b, empty, full_b, full);
        end else begin
            $display("[%0t] PASS: flags stable (depth unchanged) on 1-in/1-out", $time);
        end

        // check data continuity by draining and comparing against model
        while (!empty) begin
            try_dequeue(val, acc);
        end
        if (model_q.size() != 0) $error("[%0t] ERROR: model not empty after spot-check drain", $time);

        // half-way reset test
        $display("\n[EXT] 5) Reset mid-operation");

        // preload some data
        model_q.delete();
        for (int k = 0; k < 3; k++) begin
            try_enqueue(8'h80 + k, acc);
        end

        // assert reset and verify clear
        do_reset();
        model_q.delete();
        @(posedge clk);
        if (!empty) $error("[%0t] ERROR: empty not asserted after reset", $time);
        else $display("[%0t] PASS: reset cleared FIFO (empty=1)", $time);

        $display("\n[EXT] All extended tests completed.");
        $finish;
    end
endmodule
