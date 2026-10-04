# Architecture

This core is [MiSTery](https://github.com/gyurco/MiSTery) (Atari ST/STE/Mega STE for MiST) with a new
board layer for the Analogue Pocket. MiSTery's machine — `atarist/atarist_sdram.sv` and everything under it
(FX68K, GSTMCU/Shifter, Blitter, MFP, YM2149, WD1772, IKBD 6301) — is used **unmodified**, as a git
submodule pinned in `src/fpga/MiSTery`. Only `mist/mist_top.sv` and the MiST I/O controller protocol it
speaks are replaced.

```
apf_top (Analogue)
└── core_top                      src/fpga/core/core_top.v
    ├── pll_st                    74.25 MHz -> 32.084988 / 96 / 128 / 2 MHz (one VCO)
    ├── core_bridge_cmd           Analogue host/target command handler (template, unchanged)
    ├── st_media                  TOS loader + floppy sector server over target commands
    ├── hid_ps2                   Dock keyboard/mouse + pad -> PS/2 streams for the IKBD
    ├── st_video                  Shifter output -> APF scaler (fixed windows, slot select)
    ├── sound_i2s                 15-bit stereo mix -> Pocket I2S DAC (agg23, MIT)
    └── atarist_sdram             MiSTery, unchanged
```

## What replaces the MiST I/O controller

On MiST an ARM controller feeds the FPGA over SPI (`user_io.v`, `data_io.v`). Each of its jobs maps to a
Pocket mechanism:

| MiST (ARM over SPI)                         | Pocket                                                         |
|---------------------------------------------|----------------------------------------------------------------|
| TOS upload via `data_io` (`data_in_strobe`) | `st_media` pulls the TOS slot with Dataslot Read, 4 KB at a time |
| SD-card sector service (`sd_rd`/`sd_ack`)   | `st_media` issues a 512-byte Dataslot Read/Write per sector    |
| `img_mounted` / `img_size`                  | datatable scan at boot, Dataslot Update (0x008A) when a disk is picked |
| `system_ctrl` from the OSD                  | `interact.json` registers at `0x8000_00xx`                     |
| PS/2 keyboard/mouse                         | Dock HID reports (players 3/4) re-encoded as PS/2 by `hid_ps2` |
| USB joysticks                               | Pocket pads 1 and 2                                            |
| RTC                                         | APF RTC (0x0090) captured at boot                              |

## Media: why everything is deferload

All three data slots (`data.json`) are `deferload`, so APF never pushes data at its own pace. The bridge
bus has no back-pressure, while MiSTery accepts a TOS word only once per 2 MHz bus slot and the FDC wants
one sector at a time. With target commands the core asks for exactly what it can consume:

1. After `dataslot_allcomplete`, `st_media` reads the datatable (two words per slot: id, size) to find the
   floppy image sizes and mounts them (`img_mounted` pulse with `img_size`).
2. It reads TOS chunk 0, checks `os_base` (the long at offset 8): `$FC` means a 192 KB TOS at `$FC0000`,
   anything else a 256 KB TOS at `$E00000`. It then streams the ROM into SDRAM through MiSTery's
   `data_in_strobe_rom` port, one word every 64 clocks, holding the ST in reset (`tos_done` low).
3. FDC `sd_rd`: Dataslot Read of `lba*512` from slot 1 or 2 into the read buffer, then 512 bytes into the
   FDC's sector buffer. `sd_wr`: the FDC buffer is copied to the write buffer, then Dataslot Write.
4. Picking a new disk in the Pocket menu sends Dataslot Update; the drive is re-mounted. Picking a new TOS
   reloads it and resets the machine.

Bridge buffers: read buffer `0x1000_0000`–`0x1000_0FFF`, write buffer `0x1000_2000`–`0x1000_21FF`.

Clock domains: the command engine runs on `clk_74a`, everything facing MiSTery on `clk_32`. Requests cross
as a toggle handshake whose parameters are held stable until the acknowledge toggle returns.

## Memory

ST RAM (up to 14 MB) and TOS live in the Pocket's 64 MB SDRAM, driven by MiSTery's own `sdram.v`. That
controller was written for the MiST's 32 MB MT48LC16M16 (9 column bits); on the Pocket's AS4C32M16 it
simply uses half the columns. The Pocket SDRAM has no chip-select pin; `sdram.v`'s idle command
(`CMD_INHIBIT`) becomes a NOP once CS is dropped, so its command encoding works unchanged.

`dram_clk` comes from a separate PLL output leading `clk_96` by ~2 ns (`pll_st.v`), mirroring the MiST's
zero-phase board clock. This is the first thing to tune if SDRAM is unstable on hardware.

## Settings

Each `interact.json` entry writes its own register; all are read back for APF's read-modify-write.
Changing machine, RAM, CPU or monitor resets the ST (MiSTery only samples those at reset).

| Address       | Setting        | Values                                   |
|---------------|----------------|------------------------------------------|
| `0x80000000`  | Reset ST       | any write                                |
| `0x80000004`  | Machine        | 0 ST, 1 STE, 2 Mega STE                  |
| `0x80000008`  | Memory         | 0 512K, 1 1M, 2 2M, 3 4M, 4 8M, 5 14M    |
| `0x8000000C`  | Monitor        | 0 colour, 1 mono                         |
| `0x80000010`  | Blitter (ST)   | 0/1 (the STE always has one)             |
| `0x80000014`  | YM stereo      | 0/1                                      |
| `0x80000018`  | Write protect  | bit 0 drive A, bit 1 drive B             |
| `0x8000001C`  | Borders        | 0 hide, 1 show                           |
| `0x80000020`  | Pad mode       | 0 joystick, 1 mouse                      |
| `0x80000024`  | CPU            | 0 68000 (FX68K), 1 68020 (TG68K)         |

## Not ported

ACSI hard disks, MIDI, serial/parallel redirection, Ethernec, Cubase dongles and the Viking card are
tied off in `core_top.v`. ACSI would follow the same target-command pattern as the floppies.
