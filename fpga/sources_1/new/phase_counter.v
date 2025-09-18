module phase_counter (
    input baud_en,
    input clk,
    input phase_arm,
    output reg center_tick = 0,
    output reg first_tick = 0
);
    parameter integer OVERSAMPLE = 16;
    localparam integer CENTER = OVERSAMPLE/2; // Lean towards safe side of bit 
    localparam integer COUNTER_BITS = $clog2(OVERSAMPLE);

    reg [COUNTER_BITS - 1 : 0] counter = 0;

    always@(posedge clk) begin
        center_tick <= 0;
        first_tick <= 0;

        if(phase_arm) begin
            counter <= 0;
        end else begin
            if(baud_en) begin 
                if (counter == CENTER) begin
                    center_tick <= 1;
                    counter <= counter + 1;
                end else if (counter == 0) begin
                    first_tick <= 1;
                    counter <= counter + 1;
                end else if (counter == OVERSAMPLE-1) begin
                    counter <= 0;
                end else begin 
                    counter <= counter + 1;
                end
            end
        end
    end

endmodule