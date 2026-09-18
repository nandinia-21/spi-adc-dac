# SPI Master with ADC/DAC Signal Chain

An SPI master (Mode 0) in Verilog, verified against a behavioral SPI
slave, then used to build a full digitize -> transport -> reconstruct
signal chain against behavioral ADC and DAC chip models.

## Files

- `spi_master.v` - the SPI master design (synthesizable)
- `spi_master_tb.v` - self-checking testbench with a behavioral fake
  slave, verifying both directions of the full-duplex transfer
- `adc_model.v` / `dac_model.v` - behavioral chip models (not
  synthesizable. They use `real` values to stand in for an actual
  external analog chip during simulation)
- `signal_chain_tb.v` - the full signal chain test: analog voltage in,
  through the ADC over SPI, back out through the DAC, compared against
  the original

## Why this project

SPI is the transport layer for most real-world ADC/DAC chips, sensors,
and companion chips: building the master once, verified on its own,
then reusing it unmodified for the ADC/DAC signal chain mirrors how a
real embedded system would be built: a known-good peripheral driver
integrated into a larger system, rather than building everything at
once and debugging the protocol and the analog interfacing
simultaneously.

## Design decisions

**Why Mode 0 (CPOL=0, CPHA=0).**
It's the most common mode across real SPI peripherals, and simplest to
reason about: SCLK idles low, data is sampled on the rising edge, and
shifted out on the falling edge. Sampling and shifting on opposite
edges gives half a clock period of setup margin between when a bit is
driven and when it's captured, i.e. the same principle that mattered for
the async FIFO's synchronizer timing.

**Why a fixed 8-bit, single-slave transfer for the basic version.**
Multi-slave arbitration (multiple chip-selects, possibly different SPI
modes per device) and configurable transfer widths are real extensions,
but add complexity that isn't needed to demonstrate the core protocol
correctly. Scoped out deliberately rather than left unconsidered.

**Why the ADC/DAC chips are behavioral models, not real hardware or
gate-level RTL.**
No physical board was used for this pass, so the chips are modeled the
way a verification environment would model an external device it
doesn't own the design of: `adc_model.v` quantizes a `real`-valued
analog input to an 8-bit code and shifts it out over SPI; `dac_model.v`
does the reverse. This is the standard "RTL-only" route for an ADC/DAC
project- verifying the digital interface and the digitize/reconstruct
math, without needing physical analog hardware.

**Why two separate SPI masters instead of one bus with two
chip-selects.**
The signal chain uses one dedicated master per chip rather than
multiplexing a single master's chip-select between the ADC and DAC.
This kept `spi_master.v` completely unmodified rather than adding
multi-device select logic under time pressure. A real system would
more likely share one bus, noted honestly as the next extension
rather than glossed over.

## Verification approach

**SPI master, standalone (`spi_master_tb.v`):**
A behavioral fake slave shifts its own known byte out on MISO while
capturing whatever the master sends on MOSI, so both directions of the
full-duplex transfer are checked in the same test: did the master
correctly receive what the slave sent, and did the slave correctly
receive what the master sent. Directed transfers plus 20 randomized
byte pairs.

**Full signal chain (`signal_chain_tb.v`):**
A known analog voltage is driven into the ADC model, read back through
the SPI master as a digitized code, then written back out through a
second SPI master to the DAC model, and the reconstructed voltage is
compared against the original. Tolerance is set at exactly 1 LSB, the
unavoidable quantization error at this resolution, not an arbitrary
margin.

## Results

**Signal chain simulation** - every tested point reconstructed within
tolerance:

```
1 LSB = 0.0129 V at 8-bit resolution, VREF=3.30

in=0.0000  code=0    out=0.0000  err=0.0000  (limit=0.0129)
in=3.3000  code=255  out=3.3000  err=0.0000  (limit=0.0129)
in=1.6500  code=128  out=1.6565  err=0.0065  (limit=0.0129)
in=1.0000  code=77   out=0.9965  err=0.0035  (limit=0.0129)
...
PASS: all points reconstructed within 1 LSB
```

Every observed error sits at or below 0.0065V- half the 1-LSB limit,
which is exactly the expected worst case for round-to-nearest
quantization: error should never exceed half an LSB in either
direction, and it doesn't.

**Synthesis** - `spi_master.v` alone, targeting Xilinx 7-series
(`synth_xilinx -family xc7`):

```
27 flip-flops   (FDCE x26, FDPE x1)
25 LUTs         (LUT2 x8, LUT3 x10, LUT4 x3, LUT5 x3, LUT6 x1)
1  CARRY4       (bit counter / clock-divider arithmetic)
1  BUFG, 12 IBUF, 13 OBUF (clock buffering and I/O boilerplate)
```

Small and reasonable for what this is: flip-flops cover the FSM state,
the bit counter, the clock-divider counter, and the shift register; no
memory primitives are used since there's no storage array, unlike the
FIFO project. As with the FIFO, this is resource utilization only.
No place-and-route or static timing analysis was run, so there's no
real max clock frequency number to quote here.

## Extensions (not yet done)

- Multi-slave support: one SPI master, multiple chip-selects, muxed
  onto a shared bus instead of one master per device
- Configurable SPI mode (CPOL/CPHA) instead of Mode 0 only
- Real hardware: an actual SPI ADC/DAC chip over a physical board,
  replacing the behavioral models
- Place-and-route + static timing analysis for a real fmax number
