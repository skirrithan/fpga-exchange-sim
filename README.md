# FPGA Exchange Simulation

A small end-to-end exchange-stage simulator built around a SystemVerilog
ready/valid pipeline. The repo generates packet traces, schedules them through
a Rust runtime, drives the RTL with a C++ Verilator harness, and checks the
resulting decisions and latency.

## Architecture

```text
python trace generator
  -> binary_traces/packets.pb

Rust runtime
  -> binary_traces/sim_input.pb

C++ Verilator harness + SystemVerilog RTL
  -> results/output.csv
  -> sim_cpp/build/waves/stage_transform.vcd

Python checker
  -> pass/fail validation
```

```text
                         +-----------------------------+
                         |      proto/packet.proto     |
                         | shared Packet / DMA schema  |
                         +--------------+--------------+
                                        |
                  +---------------------+----------------------+
                  |                                            |
                  v                                            v
        +--------------------+                    +--------------------------+
        | Rust prost-build   |                    | protoc --cpp_out        |
        | generated types    |                    | sim_cpp/cpp_pb/*.cc/.h  |
        +----------+---------+                    +------------+-------------+
                   |                                           |
                   v                                           v

+-----------------------------+      +-----------------------------+
| python_module/              |      | rust_runtime/src/main.rs    |
| gen_trace_proto.py          |      |                             |
|                             |      | reads PacketTrace           |
| creates fixed test packets  +----->+ wraps packets as            |
|                             |      | DmaDescriptor records       |
+--------------+--------------+      +--------------+--------------+
               |                                    |
               v                                    v
+-----------------------------+      +-----------------------------+
| binary_traces/packets.pb    |      | binary_traces/sim_input.pb  |
| PacketTrace                 |      | DmaTrace                    |
+-----------------------------+      +--------------+--------------+
                                                   |
                                                   v
                                      +-----------------------------+
                                      | sim_cpp/main.cpp            |
                                      | Verilator C++ harness       |
                                      |                             |
                                      | reads sim_input.pb          |
                                      | drives ready/valid inputs   |
                                      | applies output stalls       |
                                      +--------------+--------------+
                                                     |
                                                     v
                                      +-----------------------------+
                                      | rtl/stage_transform.sv      |
                                      | Verilated as Vstage_transform|
                                      |                             |
                                      | market-data filter          |
                                      | sequence-gap check          |
                                      | order risk check            |
                                      | ready/valid backpressure    |
                                      +--------------+--------------+
                                                     |
                         +---------------------------+---------------------------+
                         |                                                       |
                         v                                                       v
          +-----------------------------+                         +-----------------------------+
          | results/output.csv          |                         | sim_cpp/build/waves/        |
          | actions, flags, latency     |                         | stage_transform.vcd         |
          +--------------+--------------+                         | waveform trace              |
                         |                                        +-----------------------------+
                         v
          +-----------------------------+
          | python_module/              |
          | check_results.py            |
          |                             |
          | validates expected actions, |
          | flags, packet presence,     |
          | and latency invariants      |
          +--------------+--------------+
                         |
                         v
                  +-------------+
                  | PASS / FAIL |
                  +-------------+
```

## Main Flow

Run the full simulation with:

```sh
make all
```

This runs:

1. `trace` - generate `binary_traces/packets.pb`.
2. `rust` - convert packets into DMA-style descriptors.
3. `cpp_proto` - generate C++ protobuf bindings.
4. `build` - Verilate the RTL and C++ harness.
5. `run` - execute the simulator.
6. `check` - validate output decisions and latency.

## Components

| Path | Purpose |
| --- | --- |
| `proto/packet.proto` | Shared packet, DMA descriptor, and trace schema. |
| `python_module/gen_trace_proto.py` | Creates a fixed six-packet input trace. |
| `rust_runtime/src/main.rs` | Wraps packets as scheduled DMA descriptors. |
| `rtl/stage_transform.sv` | Active SystemVerilog ready/valid processing stage. |
| `sim_cpp/main.cpp` | Verilator harness that drives RTL and writes results. |
| `python_module/check_results.py` | Validates expected actions, flags, and latency. |

## RTL Behavior

`rtl/stage_transform.sv` is a one-entry ready/valid stage:

```systemverilog
assign in_ready = !full || (out_valid && out_ready);
assign out_valid = full;
```

It performs:

- Market-data filtering: accept symbol `101`, drop other symbols.
- Sequence tracking: flag sequence gaps with `FLAG_SEQ_GAP`.
- Order risk checks: reject orders where `qty > 100` or `price > 2000`.
- Backpressure handling through `in_valid/in_ready` and `out_valid/out_ready`.

Action codes:

| Code | Meaning |
| --- | --- |
| `0` | `ACTION_DROP` |
| `1` | `ACTION_ACCEPT` |
| `2` | `ACTION_REJECT` |

Flag codes:

| Code | Meaning |
| --- | --- |
| `0` | `FLAG_NONE` |
| `1` | `FLAG_SEQ_GAP` |
| `2` | `FLAG_RISK_FAIL` |
| `4` | `FLAG_SYMBOL` |

## Test Trace

The generated trace intentionally covers the main behaviors:

| Packet | Scenario | Expected result |
| --- | --- | --- |
| `0` | Valid market data, symbol `101`, seq `1` | Accept |
| `1` | Valid market data, symbol `101`, seq `2` | Accept |
| `2` | Market data for wrong symbol `202` | Drop with symbol flag |
| `3` | Market data with sequence gap | Accept with gap flag |
| `4` | Valid order | Accept |
| `5` | Oversized order quantity | Reject with risk flag |

## Outputs

The simulator writes:

- `results/output.csv` - packet decisions, flags, and latency.
- `sim_cpp/build/waves/stage_transform.vcd` - waveform trace.

The C++ harness also injects downstream stalls:

```cpp
top->out_ready = (cycle % 5 != 0);
```

Every fifth cycle, the downstream consumer is not ready, which exercises
backpressure and can increase packet latency.

## Cleanup

Remove generated simulation artifacts with:

```sh
make clean
```

## Notes

- `rtl/stage_transform_old.sv` is an older payload-increment stage and is not
  used by the current make flow.
- `proto/packet_s1.proto` is an older minimal packet schema and is not used by
  the current build.
- `python_module/sim_step1.py` is a standalone Python toy model and is not used
  by the current build.
