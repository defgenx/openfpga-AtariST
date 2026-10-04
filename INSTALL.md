# Installing the Atari ST core on the Analogue Pocket

## 1. Copy the core to the microSD card

Take the `defgenx.AtariST.zip` produced by `./build.sh` (or the `release/` folder) and copy its
contents to the **root** of the Pocket's microSD card, merging with the folders already there:

```
SD card root
├── Assets/
│   └── atarist/
│       └── common/              <- your TOS ROM and .st disk images go here
├── Cores/
│   └── defgenx.AtariST/
│       ├── atarist.rbf_r        <- the core bitstream
│       ├── core.json  data.json  input.json  interact.json  video.json ...
└── Platforms/
    └── atarist.json
```

On macOS, copy the folders with Finder or `ditto`. Don't replace the existing `Assets`, `Cores` or
`Platforms` folders; merge into them. Eject the card cleanly afterwards.

## 2. Add a TOS ROM (required)

The ST needs its operating system ROM (TOS), which is copyrighted and not included. Use a dump of your
own machine's TOS.

1. Copy the image to `Assets/atarist/common/`.
2. Name it `tos.img` to have it load automatically. Otherwise the Pocket asks you to pick a file the
   first time you start the core.

Accepted: raw TOS images of **192 KB** (TOS 1.00, 1.02, 1.04) or **256 KB** (TOS 1.06, 1.62, 2.06),
with the extension `.img`, `.rom`, `.bin` or `.tos`. The core reads the ROM header and places it at the
right address itself.

| Machine setting | TOS that works                         |
|-----------------|----------------------------------------|
| ST              | 1.00, 1.02, 1.04, 2.06                 |
| STE             | 1.06, 1.62, 2.06                       |
| Mega STE        | 2.05, 2.06                             |

TOS 1.04 (ST) and TOS 2.06 (any machine) are the most compatible choices. Split dumps (separate
high/low byte files from the ROM chips) must be merged into one file first. TT and Falcon TOS (3.x, 4.x)
won't work.

To switch to a different TOS later, use *Core Settings → TOS* in the Pocket menu. The ST resets with
the new ROM.

## 3. Add floppy disks (optional)

Copy `.st` disk images to `Assets/atarist/common/`, then load them from the core's menu:
*Core Settings → Floppy A* (or *Floppy B*). You can swap disks while the ST is running.

* Only raw `.st` images are supported. Convert `.msa` or `.stx` images to `.st` first (for example with
  Hatari's `hmsa` tool: `hmsa game.msa` produces `game.st`).
* Disks are **write-protected by default**. To let games save, set *Core Settings → Write Protect* to
  *None*. Keep backups: disk writing is new and untested on hardware.

## 4. Start it

On the Pocket: *openFPGA → Atari ST*. The GEM desktop (or your boot disk) appears after a second or two.

Useful settings (*Core Settings*):

| Setting       | What it does                                              |
|---------------|-----------------------------------------------------------|
| Machine       | ST / STE / Mega STE (resets the ST)                       |
| Memory        | 512 KB to 14 MB; 1 MB is the default (resets the ST)      |
| Monitor       | Colour, or Mono for 640×400 high-res software             |
| Pad Mode      | Joystick, or Mouse (D-pad moves the GEM pointer)          |
| Borders       | Show or hide the screen borders                           |
| Reset ST      | Warm reset                                                |

## Controls

| Pocket button | Joystick mode       | Mouse mode   |
|---------------|---------------------|--------------|
| D-pad         | Joystick            | Move pointer |
| A             | Fire                | Left click   |
| B             | Fire 2              | Right click  |
| X             | Space               | Space        |
| Y             | Return              | Return       |

In the Dock, a USB keyboard and mouse work as the real ST keyboard and mouse. Page Up = Help,
Page Down = Undo.

## Troubleshooting

* **Black screen, nothing happens:** the TOS file is missing or not a raw 192/256 KB image. Check that it
  is in `Assets/atarist/common/` and its size is exactly 196,608 or 262,144 bytes.
* **Bombs or a crash at boot:** the TOS doesn't match the machine (e.g. TOS 1.06 with *Machine = ST*).
  See the table in step 2.
* **Disk not seen:** only `.st` images work; set the disk in *Floppy A* before booting a game that
  needs it, then use *Reset ST*.
* **Image off-centre in mono mode:** a known gap in this first version, see `docs/video.md`.
