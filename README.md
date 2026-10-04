# Atari ST for Analogue Pocket

An openFPGA port of [MiSTery](https://github.com/gyurco/MiSTery), Gyorgy Szombathelyi's cycle-accurate
Atari ST/STE/Mega STE core for the MiST board, to the Analogue Pocket.

> **Status: untested on hardware.** The Pocket-specific modules are simulated (see *Tests*) and every
> source has passed Verilator lint, but the core has not yet run on a Pocket. Expect the first
> hardware session to need fixes — the open points are listed under *Known gaps*.

## Features

* ST, STE and Mega STE (16 MHz) machines, 512 KB – 14 MB RAM, 68000 (FX68K) or 68020 (TG68K)
* Any 192 KB or 256 KB TOS image; picking another TOS from the menu reloads it
* Two floppy drives using `.st` images, read **and write**, swappable from the Pocket menu
* Colour (low/medium res, PAL and NTSC, borders on or off) and monochrome 640×400
* YM2149 + STE DMA sound, Blitter
* Dock USB keyboard and mouse; Pocket pad as joystick or as mouse

## Installing

See **[INSTALL.md](INSTALL.md)**: copying to the microSD card, adding a TOS ROM (192 or 256 KB,
`.img`/`.rom`/`.bin`/`.tos`) and floppy images, settings, controls and troubleshooting.

## Controls

See [docs/input.md](docs/input.md). In short: pad 1 is the ST joystick (A fire, B fire 2, X Space,
Y Return); set *Pad Mode* to *Mouse* to drive the GEM pointer with the D-pad (A/B = left/right click).
A keyboard and mouse plugged into the Dock work as on a real ST.

## Building

Requirements: Quartus Prime Lite (the Pocket's Cyclone V 5CEBA4), or Docker, plus Python 3.

```sh
git clone --recursive <this repo>
./build.sh            # compile (native quartus_sh if on PATH, else the raetro/quartus Docker image) and package
./build.sh package    # only package an existing src/fpga/output_files/ap_core.rbf
```

On Apple Silicon the Docker build runs under x86 emulation and is slow; the image needs ~15 GB of free
space in Docker's VM.

## Tests

```sh
make -C sim           # needs Icarus Verilog and Verilator
```

* `media` / `media256`: `st_media` against a model of APF's target commands and datatable — 192 KB
  and 256 KB TOS loads (addresses and data, word by word), sector read, sector write, disk mount and swap.
* `hid`: `hid_ps2` driving MiSTery's own IKBD PS/2 decoder — key matrix (including extended keys and
  modifiers) and exact mouse quadrature counts.
* `video`: `st_video` with the measured PAL/NTSC/mono sync timing — every frame has the scaler mode's
  exact width, height and slot id.

## Known gaps

* Not yet run on hardware: SDRAM clock phase, Dock HID field layout and the datatable layout are taken
  from Analogue's examples and need confirming.
* Mono and medium-res horizontal positions are estimated ([docs/video.md](docs/video.md)).
* The RTC is set once at boot and does not tick.
* No hard disk (ACSI), MIDI, serial/parallel, `.msa`/`.stx` images or on-screen keyboard.

## Documentation

* [docs/architecture.md](docs/architecture.md) — how the MiST board layer was replaced, media flow, settings map
* [docs/video.md](docs/video.md) — measured ST video timing and scaler windows
* [docs/input.md](docs/input.md) — controls, Dock keyboard/mouse translation

## Credits and licence

* [MiSTery](https://github.com/gyurco/MiSTery) by Gyorgy Szombathelyi, with FX68K and the Blitter by
  Jorge Cwik, the IKBD by Till Harbaum and the GSTMCU schematics recovered by Christian Zietz — GPL.
  Included unmodified as a submodule.
* Analogue's [openFPGA core template](https://github.com/open-fpga/core-template) (`src/fpga/apf`,
  `core_bridge_cmd.v`).
* `sound_i2s.sv` and `sync_fifo.sv` from [analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)
  by Adam Gastineau — MIT.

The Pocket-specific code in this repository is distributed under the GPL, like the MiSTery core it
builds on.
