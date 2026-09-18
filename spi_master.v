`timescale 1ns/1ps

module spi_master #(
    parameter DATA_WIDTH = 8,
    parameter CLK_DIV    = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  start,
    input  wire [DATA_WIDTH-1:0] tx_data,
    output reg  [DATA_WIDTH-1:0] rx_data,
    output reg                   busy,
    output reg                   done,

    output wire                  sclk,
    output reg                   cs_n,
    output wire                  mosi,
    input  wire                  miso
);

    localparam IDLE   = 2'b00;
    localparam LOAD   = 2'b01;
    localparam SHIFT  = 2'b10;
    localparam FINISH = 2'b11;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] shift_reg;
    reg [$clog2(DATA_WIDTH)-1:0] bit_cnt;
    reg [$clog2(CLK_DIV)-1:0] clk_cnt;
    reg sclk_int;

    assign sclk = sclk_int;
    assign mosi = shift_reg[DATA_WIDTH-1];

    wire clk_tick = (clk_cnt == (CLK_DIV/2 - 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= 0;
            sclk_int <= 1'b0;
        end
        else if (state == SHIFT) begin
            if (clk_tick) begin
                clk_cnt  <= 0;
                sclk_int <= ~sclk_int;
            end
            else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
        else begin
            clk_cnt  <= 0;
            sclk_int <= 1'b0;
        end
    end

    wire sclk_rising =
        (state == SHIFT) && clk_tick && (sclk_int == 1'b0);

    wire sclk_falling =
        (state == SHIFT) && clk_tick && (sclk_int == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            shift_reg <= 0;
            rx_data   <= 0;
            bit_cnt   <= 0;
            busy      <= 1'b0;
            done      <= 1'b0;
            cs_n      <= 1'b1;
        end
        else begin
            done <= 1'b0;

            case (state)

                IDLE: begin
                    cs_n <= 1'b1;
                    busy <= 1'b0;

                    if (start) begin
                        shift_reg <= tx_data;
                        bit_cnt   <= DATA_WIDTH - 1;
                        cs_n      <= 1'b0;
                        busy      <= 1'b1;
                        state     <= SHIFT;
                    end
                end

                SHIFT: begin
                    if (sclk_rising) begin
                        rx_data <= {rx_data[DATA_WIDTH-2:0], miso};
                    end

                    if (sclk_falling) begin
                        if (bit_cnt == 0) begin
                            state <= FINISH;
                        end
                        else begin
                            shift_reg <= shift_reg << 1;
                            bit_cnt   <= bit_cnt - 1'b1;
                        end
                    end
                end

                FINISH: begin
                    cs_n  <= 1'b1;
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule