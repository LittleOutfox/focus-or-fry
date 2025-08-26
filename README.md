# Focus-or-Fry

**Wearable neurofeedback experiment.** Listens to my brainwaves (EEG) and reacts when I lose focus by buzzing, zapping, or otherwise nagging me back on task. Built as a passion project to explore **FPGA (Verilog)** + **embedded C++ (MCU)**.

---

## MVP (Minimum Viable Product)
- [ ] MCU reads an 0–100 “attention” value (real or synthetic)
- [ ] MCU sends UART packets with CRC to FPGA
- [ ] FPGA parses packets and computes a rolling average
- [ ] FPGA asserts `focus_lost` and drives **LED** (then vibration)
- [ ] Safety: reset button; watchdog → outputs OFF when stream stops

**Stretch (later):** adaptive thresholds, nicer telemetry, optional TENS via opto trigger.

---

## System sketch
```mermaid
flowchart LR
  EEG[EEG: attention 0–100] --> MCU[MCU: Embedded C++]
  MCU -->|UART packets| FPGA[FPGA: Verilog]
  FPGA --> Logic[Rolling avg + debounce + FSM]
  Logic --> Out[Vibration / LED]
  Btn[Reset button] --> FPGA
  FPGA --> Status[Status back to MCU/USB]
