`timescale 1ns/1ps

module signal_chain_tb;

    parameter DATA_WIDTH = 8;
    parameter CLK_DIV    = 4;
    parameter real VREF  = 3.3;

    reg clk, rst_n;
    integer errors;

    // ADC-side SPI master 
    reg                   adc_start;
    reg  [DATA_WIDTH-1:0] adc_tx_data;   // dummy
    wire [DATA_WIDTH-1:0] adc_rx_data;   // digitized code comes back here
    wire                  adc_busy, adc_done;
    wire                  adc_sclk, adc_cs_n, adc_mosi, adc_miso;

    // DAC-side SPI master 
    reg                   dac_start;
    reg  [DATA_WIDTH-1:0] dac_tx_data;   // code to send to the DAC
    wire [DATA_WIDTH-1:0] dac_rx_data;   // unused
    wire                  dac_busy, dac_done;
    wire                  dac_sclk, dac_cs_n, dac_mosi, dac_miso;

    // chip models
    real analog_in;
    real analog_out;

    spi_master #(.DATA_WIDTH(DATA_WIDTH), .CLK_DIV(CLK_DIV)) m_adc (
        .clk(clk), .rst_n(rst_n),
        .start(adc_start), .tx_data(adc_tx_data), .rx_data(adc_rx_data),
        .busy(adc_busy), .done(adc_done),
        .sclk(adc_sclk), .cs_n(adc_cs_n), .mosi(adc_mosi), .miso(adc_miso)
    );

    spi_master #(.DATA_WIDTH(DATA_WIDTH), .CLK_DIV(CLK_DIV)) m_dac (
        .clk(clk), .rst_n(rst_n),
        .start(dac_start), .tx_data(dac_tx_data), .rx_data(dac_rx_data),
        .busy(dac_busy), .done(dac_done),
        .sclk(dac_sclk), .cs_n(dac_cs_n), .mosi(dac_mosi), .miso(dac_miso)
    );

    adc_model #(.DATA_WIDTH(DATA_WIDTH), .VREF(VREF)) adc (
        .cs_n(adc_cs_n), .sclk(adc_sclk), .mosi(adc_mosi), .miso(adc_miso),
        .analog_in(analog_in)
    );

    dac_model #(.DATA_WIDTH(DATA_WIDTH), .VREF(VREF)) dac (
        .cs_n(dac_cs_n), .sclk(dac_sclk), .mosi(dac_mosi),
        .analog_out(analog_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // One LSB of quantization error, in volts
    real lsb_volts;

    task run_point(input real v_in);
        real err;
        begin
            analog_in = v_in;

            // step 1: read the ADC
            @(posedge clk);
            adc_tx_data = 8'h00;
            adc_start   = 1'b1;
            @(posedge clk);
            adc_start   = 1'b0;
            wait (adc_done == 1'b1);
            @(posedge clk);

            // step 2: write that code to the DAC 
            dac_tx_data = adc_rx_data;
            @(posedge clk);
            dac_start   = 1'b1;
            @(posedge clk);
            dac_start   = 1'b0;
            wait (dac_done == 1'b1);
            @(posedge clk);
            #1; // let dac_model's posedge cs_n block settle

            err = analog_out - v_in;
            if (err < 0) err = -err;

            $display("[%0t] in=%.4f  code=%0d  out=%.4f  err=%.4f (limit=%.4f)",
                      $time, v_in, adc_rx_data, analog_out, err, lsb_volts);

            if (err > lsb_volts + 1e-6) begin
                $display("        ERROR: reconstruction error exceeds 1 LSB");
                errors = errors + 1;
            end
        end
    endtask

    integer i;

    initial begin
        errors      = 0;
        rst_n       = 0;
        adc_start   = 0;
        dac_start   = 0;
        adc_tx_data = 0;
        dac_tx_data = 0;
        analog_in   = 0.0;
        lsb_volts   = VREF / ((1 << DATA_WIDTH) - 1);

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("Signal chain: ADC -> SPI -> DAC");
        $display("1 LSB = %.4f V at %0d-bit resolution, VREF=%.2f", lsb_volts, DATA_WIDTH, VREF);

        run_point(0.0);
        run_point(VREF);
        run_point(VREF / 2.0);
        run_point(1.0);
        run_point(2.5);

        // sweep a handful of points across the range
        for (i = 0; i < 10; i = i + 1)
            run_point((VREF * i) / 10.0);

        if (errors == 0)
            $display("PASS: all points reconstructed within 1 LSB");
        else
            $display("FAIL: %0d point(s) exceeded tolerance", errors);

        $finish;
    end

endmodule