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
| RTC                                         | APF RTC (0x0090) at boot, then a BCD clock ticking every second |

## Media: why everything is deferload

All three data slots (`data.json`) are `deferload`, so APF never pushes data at its own pace. The bridge
bus has no back-pressure, while MiSTery accepts a TOS word only once per 2 MHz bus slot and the FDC wants
one sector at a time. With target commands the core asks for exactly what it can consume:

1. After `dataslot_allcomplete`, `st_media` reads the datatable (two words per slot: id, size) to find the
   floppy image sizes and mounts them (`img_mounted` pulse with `img_size`).
2. It reads TOS in 16 KB chunks. From chunk 0 it checks `os_base` (the long at offset 8): `$FC` means a 192 KB TOS at `$FC0000`,
   anything else a 256 KB TOS at `$E00000`. It then streams the ROM into SDRAM through MiSTery's
   `data_in_strobe_rom` port, one word every 32 clocks (MiSTery takes one per 16-clock bus slot),
   holding the ST in reset (`tos_done` low) behind the loading screen, which covers the whole time
   `tos_done` is low, including the wait for `dataslot_allcomplete`. Restart requests that arrive
   while TOS is loading are dropped: the ST is still in reset, so new settings apply when it starts.
3. FDC `sd_rd`: Dataslot Read of `lba*512` from slot 1 or 2 into the read buffer, then 512 bytes into the
   FDC's sector buffer. `sd_wr`: the FDC buffer is copied to the write buffer, then Dataslot Write.
4. Picking a new disk in the Pocket menu sends Dataslot Update; the drive is re-mounted. Picking a new TOS
   reloads it and resets the machine.

Bridge buffers: read buffer `0x1000_0000`–`0x1000_3FFF` (16 KB), write buffer `0x1000_8000`–`0x1000_81FF`.

Clock domains: the command engine runs on `clk_74a`, everything facing MiSTery on `clk_32`. Requests cross
as a toggle handshake whose parameters are held stable until the acknowledge toggle returns.

## Memory

ST RAM (up to 14 MB) and TOS live in the Pocket's 64 MB SDRAM, driven by MiSTery's own `sdram.v`. That
controller was written for the MiST's 32 MB MT48LC16M16 (9 column bits); on the Pocket's AS4C32M16 it
simply uses half the columns. The Pocket SDRAM has no chip-select pin; `sdram.v`'s idle command
(`CMD_INHIBIT`) becomes a NOP once CS is dropped, so its command encoding works unchanged.

### SDRAM clock

`dram_clk` is a separate PLL output (`clk_96_sd`) that leads `clk_96` by 4.06 ns, driven out through a
DDIO register (`pin_ddio_clk`) so the clock pin has the same I/O delay as the data and command pins.
Without the DDIO register the clock left through the clock network about 5.8 ns later than the data,
and no phase could satisfy read setup and hold at once.

The phase comes from the read latency `sdram.v` expects (inherited from MiST): CL2 data must sit in
`sd_din` on the `clk_96` edge after the one matching the SDRAM's read edge. With the datasheet-style
delays in `core_constraints.sdc` (tAC 6.4 ns, tOH 3.2 ns, setup 1.5 ns, hold 0.8 ns) the workable lead
is about 3.3–4.7 ns. Phase shifts must be multiples of 1/8 of the 770.04 MHz VCO period (162.33 ps);
4.06 ns is 39 steps.

This is the first thing to tune if SDRAM is unstable on hardware: change `phase_shift3` in `pll_st.v`
by whole steps.

## Settings

Each `interact.json` entry writes its own register; all are read back, so APF shows (and saves) whatever
the core holds. Changing machine, RAM, CPU or monitor triggers a **cold restart**: `st_media` holds the ST
in reset, zeroes `$0`–`$FFF` (TOS's memvalid magic at `$420`/`$43A`/`$51A`) and reloads TOS. A warm
reset would keep the magic, and TOS would skip memory sizing and keep a stale memory configuration.

| Address       | Setting        | Values                                   |
|---------------|----------------|------------------------------------------|
| `0x80000000`  | Reset ST (warm) | any write                               |
| `0x80000004`  | Machine        | 0 ST, 1 STE, 2 Mega STE, 3 STE Turbo (STEroids), 4 Auto (default) |
| `0x80000008`  | Memory         | 0 512K, 1 1M, 2 2M, 3 4M, 4 8M, 5 14M    |
| `0x8000000C`  | Monitor        | 0 colour, 1 mono                         |
| `0x80000010`  | Blitter (ST)   | 0/1 (the STE always has one)             |
| `0x80000014`  | YM stereo      | 0/1                                      |
| `0x80000018`  | Write protect  | bit 0 drive A, bit 1 drive B             |
| `0x8000001C`  | Borders        | 0 hide, 1 show                           |
| `0x80000020`  | Pad mode       | 0 joystick, 1 mouse (default), 2 keys    |
| `0x80000030`  | Mouse speed    | 0 slow, 1 normal, 2 fast                 |
| `0x80000034`  | STE Joypad Ports | any write: presses F11 (IKBD port switch) |
| `0x80000038`  | Link port      | 0 off, 1 MIDI, 2 serial                  |
| `0x8000003C`  | Cubase dongle  | 0 off, 1 on                              |
| `0x80000040`  | Screen fit     | 0 original aspect, 1 fill (10:9 scaler slots, see `video.md`) |
| `0x80000028`  | Cold Restart   | any write                                |
| `0x8000002C`  | Reset All Settings | any write: every register to its default, then a cold restart |

## TOS / machine sync

While loading TOS, `st_media` reads the header: `os_version` (offset 2) and EmuTOS's `ETOS` magic
(offset `$2C`). With *Machine = Auto*, `core_top` maps TOS 1.06/1.62 to the STE, TOS 2.05 to the Mega
STE and everything else (TOS 1.0x, 2.06, any EmuTOS) to the ST; for original TOS the RAM setting is
capped at 4 MB. The ST is in reset during the load, so it starts with the matching configuration.

## ACSI hard disks

On MiST/MiSTer the ARM answers ACSI commands; here `acsi_ctrl.sv` does it in logic. MiSTery's `acsi.v`
collects the command bytes (6 or 10, ICD prefix included) and raises *busy*; `acsi_ctrl` reads them
through `dio_status_index`, executes the command and toggles `dio_dma_ack` with the SCSI status.
Supported: TEST UNIT READY, REQUEST SENSE, READ/WRITE (6 and 10), INQUIRY, MODE SENSE(6),
READ CAPACITY; FORMAT, SEEK, VERIFY, MODE SELECT, START/STOP and RESERVE/RELEASE succeed without
doing anything; anything else answers CHECK CONDITION / ILLEGAL REQUEST. Data moves one word per
128 clocks through `dma.v`'s 16-word FIFO (~500 KB/s); short responses are padded to the FIFO's
16-byte bursts. Sectors come from data slots 3 and 4 through `st_media`, which serves them with the
floppy path but a separate `hd_ack`. `sim/system` boots EmuTOS with a FAT16 image and checks it mounts C:.

## Not ported

Serial/printer redirection, Ethernec, Cubase dongles and the Viking card are tied off in `core_top.v`:
the Pocket has no port for the first ones, and its scaler cannot take Viking's 1280×1024.

## Link port: MIDI and serial

*Link Port* = MIDI routes the MIDI ACIA (31,250 baud, its native rate) to link SO/SI; = Serial routes the
MFP's UART instead (`serial_redirect` off, so MiSTery uses its real UART at the baud software sets). SI is
synchronised to `clk_32`. Off, SO is tri-stated and both RX lines idle high. A Game Boy link cable crosses
SO/SI, which makes two Pockets a MIDI ring (MIDI Maze) or a null-modem pair.

## Cartridge

Data slot 5 is loaded after TOS by the same loader, at word `$7D0000` (byte `$FA0000`), where MiSTery's
`rom3`/`rom4` decode reads it; a 131,076-byte file has Hatari's 4-byte header skipped. Picking a
cartridge re-runs the boot sequence (low-RAM clear, TOS, cartridge).
