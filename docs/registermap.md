\# ELM Accelerator – Preliminary Register Map


The current hardware prototype is operated directly from the DE1-SoC board through switches and buttons. However, the internal control structure already follows a register-oriented model, which can be naturally exposed through MMIO in a future HPS-to-FPGA integration.


Base Address: `0xFF200000` (example for the DE1-SoC Lightweight HPS-to-FPGA AXI Bridge)


| Offset | Register | R/W | Description |

\|--------|----------|-----|-------------|

| `0x00` | INSTR    | W   | 32-bit instruction register used to encode opcode, demo address, and demo write data |

| `0x04` | STATUS   | R   | Packed status register with busy/done/error/loaded flags and prediction mirror |

| `0x08` | RESULT   | R   | Predicted digit (0–9) |

| `0x0C` | CYCLES   | R   | Reserved for future cycle counting support |


\---


\## INSTR Register (`0x00`)


The accelerator is controlled through a single instruction word.


\### Instruction format

| Bits | Name | Description |

\|------|------|-------------|

| `[31:30]` | `CMD` | Opcode field |

| `[6:4]`   | `ADDR` | Demo store address field |

| `[3:0]`   | `DATA` | Demo store data field |


\### Opcode encoding

| Value | Operation |

\|-------|-----------|

| `2'b00` | `STORE\_WEIGHTS` |

| `2'b01` | `STORE\_BIAS` |

| `2'b10` | `STORE\_IMG` |

| `2'b11` | `START` |


\### Notes

- The `ADDR` and `DATA` fields are used only by the store operations.
- For `START`, those fields are ignored.
- In the current board-level version, instruction validation is triggered by the command button (`KEY[1]`).


\---


\## STATUS Register (`0x04`)


The status signal is internally packed as a 32-bit word.


\### Status bit layout

| Bit | Name | Description |

\|-----|------|-------------|

| `0` | `BUSY` | Accelerator is running |

| `1` | `DONE` | Inference finished |

| `2` | `ERROR` | Error condition detected |

| `3` | `IMG\_LOADED` | Image buffer has been written/marked as loaded |

| `4` | `WEIGHTS\_LOADED` | Hidden-layer weights have been written/marked as loaded |

| `5` | `BIAS\_LOADED` | Bias memory has been written/marked as loaded |

| `6` | `BETA\_LOADED` | Beta coefficients available (fixed as loaded in the current version because `beta` is stored in ROM) |

| `7` | `STARTED\_ONCE` | At least one start command has already been issued |

| `[11:8]` | `PRED` | Prediction mirror |

| `[31:12]` | Reserved | Reserved for future expansion |


\---


\## RESULT Register (`0x08`)


| Bits | Name | Description |

\|------|------|-------------|

| `[3:0]` | `PRED` | Predicted digit from the `argmax10` block |


This register mirrors the final classification result and is valid when the computation is complete.


\---


\## CYCLES Register (`0x0C`)


Reserved for a future enhancement.


Planned purpose:

- store the total number of cycles used by the last inference
- support deterministic latency analysis
- assist profiling and serial-vs-parallel comparisons


At the current project stage, this register is \*\*not yet implemented in hardware\*\*.


\---


\## Operational protocol


The operational protocol follows the expected Start → Execute → Done model:


1. Software/user writes the instruction word to `INSTR`
1. The command is validated
1. If `CMD = START`, the accelerator enters processing mode
1. `STATUS.BUSY` is asserted during execution
1. When the pipeline finishes, `STATUS.DONE` is asserted
1. The predicted digit becomes available in `RESULT`


\---


\## Current board-level prototype note


In the current DE1-SoC demonstration:

- `INSTR` is assembled from board switches
- command execution is confirmed by `KEY[1]`
- status visualization is captured through a dedicated board interaction path


This MMIO map should therefore be interpreted as a \*\*preliminary architectural mapping\*\*, consistent with the internal signals already implemented in hardware.
