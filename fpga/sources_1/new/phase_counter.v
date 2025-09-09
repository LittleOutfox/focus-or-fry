module phase_counter (
    input baud_en,
    input clk,
    output reg center_tick = 0,
    output reg mid_sample;
);
    parameter integer OVERSAMPLE = 16;
    localparam integer CENTER = OVERSAMPLE/2; // Lean towards safe side of bit 
    localparam integer COUNTER_BITS = $clog2(OVERSAMPLE);

    reg [COUNTER_BITS - 1 : 0] counter = 0;

    always@(posedge clk) begin
        center_tick <= 0;
        if (baud_en) begin 
            if (counter == CENTER) begin
                counter <= counter + 1;
                center_tick <= 1;
            end else if (counter != OVERSAMPLE - 1) begin
                counter <= counter + 1;
            end else begin 
                counter <= 0;
            end
        end else begin // Implied flip-flop else statement for readibility
            counter <= counter;
        end
    end
    
    // NEED TO ADD BITS 7/8/9 MIDSAMPLING STILL

endmodule