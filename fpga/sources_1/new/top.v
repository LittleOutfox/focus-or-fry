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


module top(
    input clk,
    output led
);
    reg [25:0] counter = 0;
    reg LED_status = 0;
    
    assign led = LED_status; 
    
    // clock signal every half a second    
    always@(posedge clk) begin
        if (counter == 26'd50000000) begin
            counter <= 0;
            LED_status <= !LED_status;
        end else begin
            counter <= counter + 1;
        end
    end
    
endmodule
