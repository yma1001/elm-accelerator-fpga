\## FPGA Resource Utilization (Cyclone V)


The hardware accelerator was synthesized in Intel Quartus Prime targeting the Cyclone V FPGA available on the DE1-SoC board. The current implementation prioritizes correctness, deterministic control, and compact sequential execution, which keeps the design comfortably within the device limits while still supporting the neural datapath, memory system, and control FSM.


| Resource Type | Used | Available | Utilization (%) | Description |

\|--------------|------|-----------|-----------------|-------------|

| \*\*ALMs (LUTs)\*\* | 2251 | 32,070 | 7.02% | Combinational logic for the main FSM, pipeline phase control, instruction decode, multiplexers, argmax comparisons, address generation, and fixed-point support logic |

| \*\*Registers (FFs)\*\* | 2684 | 128,280 | 2.09% | State registers, indices, accumulators, status flags, internal buffers, and control synchronization |

| \*\*Block Memory\*\* | 1,640,704 bits | 397 M10K blocks | ~40.31% equivalent | On-chip memory used mainly by `ram\_img`, `ram\_w\_in`, `ram\_b`, and `rom\_beta`; reported here as total block memory bits from Quartus |

| \*\*DSP Blocks\*\* | 4 | 87 | 4.60% | Hardware multipliers used in the fixed-point MAC datapath |

| \*\*Pins\*\* | 51 | 457 | 11.16% | Clock, reset, buttons, switches, LEDs, and seven-segment display connections |


\> \*Note:\* The architecture deliberately reuses the MAC datapath in a sequential fashion for both hidden-layer and output-layer accumulation. This minimizes DSP consumption and keeps the logic footprint low, while block memory usage is dominated by the storage of model parameters and input data.


\### Resource usage discussion


The synthesis results indicate that the design is logic-light and DSP-light, with only \*\*7.02% of ALMs\*\*, \*\*2.09% of registers\*\*, and \*\*4.60% of DSP blocks\*\* consumed. The most relevant cost in the current architecture is \*\*on-chip memory\*\*, which is expected because the project stores the neural model parameters (`W\_in`, `b`, `beta`) and the input image directly inside FPGA memory structures. This trade-off is appropriate for the current version of the accelerator, since it favors a simpler control structure and deterministic execution over aggressive parallel replication.
