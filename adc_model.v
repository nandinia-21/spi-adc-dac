`timescale 1ns/1ps

module adc_model #(
    parameter DATA_WIDTH = 8,
    parameter real VREF  = 3.3
)(
    input  wire        cs_n,
    input  wire        sclk,
    input  wire        mosi,
    output reg         miso,
    input  real        analog_in
);

    reg [DATA_WIDTH-1:0] code;
    reg [DATA_WIDTH-1:0] shift;

    function [DATA_WIDTH-1:0] quantize(input real v);
        real q_real;
        integer q_int;
        begin
            q_real = (v / VREF) * ((1 << DATA_WIDTH) - 1) + 0.5;
            q_int  = $rtoi(q_real);

            if (q_int < 0)
                q_int = 0;
            else if (q_int > (1 << DATA_WIDTH) - 1)
                q_int = (1 << DATA_WIDTH) - 1;

            quantize = q_int;
        end
    endfunction

    always @(negedge cs_n) begin
        code  = quantize(analog_in);
        shift = code;
        miso  = shift[DATA_WIDTH-1];
    end

    always @(negedge sclk) begin
        if (!cs_n) begin
            shift = shift << 1;
            miso  = shift[DATA_WIDTH-1];
        end
    end

endmodule