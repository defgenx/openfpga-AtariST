# Installing the Atari ST core on the Analogue Pocket

## 1. Copy the core to the microSD card

**The easy way:** put the microSD card in your computer and run the installer, from a clone of the repo
or on its own after downloading it from the release page:

| System        | Run                                                                 |
|---------------|---------------------------------------------------------------------|
| Windows       | double-click **`install.bat`** (or `.\install.ps1` in PowerShell)  |
| macOS / Linux | `./install.sh`                                                      |

It finds the Pocket SD card, asks you to confirm, copies the core, EmuTOS and this guide, and offers to
eject the card. Options: `--dry-run` / `-DryRun` shows what would be copied and changes nothing;
`--sd /Volumes/POCKET` / `-SD E:\` names the card yourself.

**It never replaces a file without asking.** Files already on the card that are identical are skipped.
For each one that differs (for example a `tos.img` you put there) it asks
`Replace it? [y]es / [N]o / [a]ll / [s]kip all`; pressing Enter keeps the card's file. Run without a
console (or with the dry-run option), it never replaces anything and lists what differs. Without a
built core next to it, the installer downloads the newest release from GitHub.

**By hand:**

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

## 2. TOS (nothing to do)

The ST needs its operating system ROM, called TOS. The release already includes **EmuTOS**, a free,
open-source TOS replacement (GPL, https://emutos.sourceforge.io), in `Assets/atarist/common/`:

| File                 | Use it for                                                    |
|----------------------|---------------------------------------------------------------|
| `tos.img`            | EmuTOS 192 KB, English. Loaded automatically; for *Machine = ST* with the 68000 (the defaults) |
| `emutos-256k-uk.img` | EmuTOS 256 KB, English. For *STE*, *Mega STE* or the 68020 CPU |
| `emutos-192k-fr.img` / `emutos-256k-fr.img` | French versions (AZERTY keyboard layout)  |

To switch, pick the file in *Core Settings → TOS*; the ST resets with it. With no disk inserted, EmuTOS
boots straight to the GEM desktop.

EmuTOS runs most well-behaved ST software, but some games and demos only work with Atari's original TOS.
If you have an original TOS dump (192 KB TOS 1.00–1.04 or 256 KB TOS 1.06/1.62/2.06, as `.img`, `.rom`,
`.bin` or `.tos`), copy it to `Assets/atarist/common/` as `tos.img`, replacing the EmuTOS one:

| Machine setting | Original TOS that works |
|-----------------|-------------------------|
| ST              | 1.00, 1.02, 1.04, 2.06  |
| STE             | 1.06, 1.62, 2.06        |
| Mega STE        | 2.05, 2.06              |

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

No keyboard needed. The scheme follows the Pocket Amiga core:

| Pocket button | Joystick mode | Mouse mode   | On-screen keyboard |
|---------------|---------------|--------------|--------------------|
| D-pad         | Joystick      | Move pointer | Move cursor        |
| A             | Fire          | Left click   | Press key          |
| B             | Fire 2        | Right click  | Close keyboard     |
| X / Y         | Space / Return| Space / Return | -                |
| L / R         | -             | Left / right click | -            |
| **Select**    | Show keyboard | Show keyboard | Close keyboard    |
| **Start**     | Mouse mode    | Joystick mode | -                 |

On the on-screen keyboard, Ctrl/Shift/Alt are sticky: press Shift, then the letter. For GEM, press
Start to use the D-pad as the mouse; press Start again to play with the joystick.

In the Dock, a USB keyboard and mouse work as the real ST keyboard and mouse (Page Up = Help,
Page Down = Undo), and an analog controller's left stick moves the mouse.

## Troubleshooting

* **Black screen, nothing happens:** `tos.img` is missing from `Assets/atarist/common/` or is not a raw
  192/256 KB image (exactly 196,608 or 262,144 bytes). Re-copy it from the release zip.
* **Bombs or a crash at boot:** the TOS doesn't match the machine, e.g. the 192 KB EmuTOS with
  *Machine = STE* or the 68020 CPU. Use `emutos-256k-uk.img` for those. See step 2.
* **A game refuses to run:** it may need Atari's original TOS rather than EmuTOS.
* **Disk not seen:** only `.st` images work; set the disk in *Floppy A* before booting a game that
  needs it, then use *Reset ST*.
* **Image off-centre in mono mode:** a known gap in this first version, see `docs/video.md`.
