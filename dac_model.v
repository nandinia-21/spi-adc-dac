`timescale 1ns/1ps

module dac_model #(
    parameter DATA_WIDTH = 8,
    parameter real VREF  = 3.3
)(
    input  wire        cs_n,
    input  wire        sclk,
    input  wire        mosi,
    output real        analog_out
);

    reg [DATA_WIDTH-1:0] rx_shift;

    always @(posedge sclk) begin
        if (!cs_n)
            rx_shift = {rx_shift[DATA_WIDTH-2:0], mosi};
    end

    
    always @(posedge cs_n) begin
        analog_out = (rx_shift * 1.0 / ((1 << DATA_WIDTH) - 1)) * VREF;
    end

endmodule