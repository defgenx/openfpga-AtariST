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
| `tos.img`            | EmuTOS 256 KB, English. Loaded automatically; autodetects the machine, so it works with every *Machine* setting |
| `emutos-192k-uk.img` | EmuTOS 192 KB, English. TOS 1 style; *Machine = ST* only |
| `emutos-192k-fr.img` / `emutos-256k-fr.img` | French versions (AZERTY keyboard layout)  |

To switch, pick the file in *Core Settings → TOS*; the ST resets with it. With no disk inserted, EmuTOS
boots straight to the GEM desktop.

EmuTOS runs most well-behaved ST software, but some games and demos only work with Atari's original TOS.
If you have an original TOS dump (192 KB TOS 1.00–1.04 or 256 KB TOS 1.06/1.62/2.06, as `.img`, `.rom`,
`.bin` or `.tos`), copy it to `Assets/atarist/common/` as `tos.img`, replacing the EmuTOS one:

Leave *Machine* on **Auto** (the default): the core reads the TOS version and picks the machine it
needs (the bundled 256 KB EmuTOS runs as an STE, the 192 KB ones as an ST), and caps memory at 4 MB
for original Atari TOS. At the end, the installer lists every TOS on the card and the machine Auto
picks for it. If you pick a machine yourself, it must match:

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

## 3b. Hard disks (optional)

Copy ACSI hard-disk images (`.hd`, `.img`, as used by Hatari and MiSTer) to `Assets/atarist/common/`
and pick them in *Core Settings → Hard Disk 0 / 1*, then *Cold Restart*. EmuTOS mounts FAT16 partitions
as C:, D: … with no driver; original Atari TOS needs a hard-disk driver installed on the image
(AHDI, HDDriver or ICD). Writing is supported, so keep a backup of images you care about.

## 3c. MIDI, serial and two-Pocket games (optional)

Set *Core Settings → Link Port* to *MIDI* or *Serial*. The link port then carries the ST's MIDI port
(31,250 baud) or its RS-232 port (any baud the software sets), at 3.3 V:

* **MIDI IN** (keyboard, sequencer → ST): Analogue's *Nanoloop Pocket to MIDI IN* cable, plugged into a
  device's MIDI OUT.
* **MIDI OUT** (ST → synth): no official cable; the standard 3.3 V DIY wiring is link port pin 2 (SO)
  through 10 Ω to DIN pin 5, and 3.3 V through 33 Ω to DIN pin 4, ground to DIN pin 2.

* **Two Pockets**: a standard Game Boy link cable crosses SO and SI, so two Pockets set to *MIDI* form a
  MIDI ring for **MIDI Maze** (set the same on both, start MIDI Maze on each), and two set to *Serial* are a
  null-modem pair for serial two-player games.

Leave it *Off* when using the link port for anything else.

## 3d. Cartridge (optional)

Pick a cartridge ROM (`.stc`, up to 128 KB; Hatari's 4-byte header is skipped) in *Core Settings →
Cartridge*; the ST cold-restarts with it plugged in at `$FA0000`. *Cubase Dongle* emulates the Cubase 2/3
copy-protection key instead.

## 4. Start it

On the Pocket: *openFPGA → Atari ST*. The GEM desktop (or your boot disk) appears after a second or two.

Useful settings (*Core Settings*):

| Setting       | What it does                                              |
|---------------|-----------------------------------------------------------|
| Machine       | ST / STE / Mega STE (resets the ST)                       |
| Memory        | 512 KB to 14 MB; 1 MB is the default (resets the ST)      |
| Monitor       | Colour, or Mono for 640×400 high-res software             |
| Pad Mode      | Mouse (default, for the desktop), Joystick or Keys        |
| Borders       | Show or hide the screen borders                           |
| Reset ST (warm) | Like the reset button on a real ST; TOS always boots again, even if a game hooked the reset |
| Cold Restart  | Clears memory, reloads TOS and restarts from scratch      |
| Reset All Settings | Puts every setting back to its default, then a cold restart |

Changing *Machine*, *Memory*, *CPU* or *Monitor* always does a cold restart, so the ST re-detects its
memory and hardware.

## Controls

**Start** cycles the pad: **Mouse** (default, for the desktop) → **Joystick** (games) → **Keys**
(keyboard games) → Mouse. A label shows the new mode for two seconds.

| Button | Mouse | Joystick | Keys | On-screen keyboard |
|---|---|---|---|---|
| D-pad | move pointer | joystick | arrow keys | move cursor |
| A | left click | fire | Space | press key |
| B | right click | fire 2 | Return | close |
| X / Y | Space / Return | Space / Return | Esc / Help | – |
| L / R | left / right click | – | F1 / F2 | – |
| **Select** | keyboard | keyboard | keyboard | close |

On the on-screen keyboard, Ctrl/Shift/Alt are sticky: press Shift, then the letter. In the Dock, a USB
keyboard and mouse work as on a real ST, and an analog stick moves the mouse.

## Troubleshooting

* **Stuck after changing a setting (black screen, bombs, bus error):** in *Core Settings* choose
  **Reset All Settings**. If you cannot reach the menu, erase the saved settings from the card with the
  installer: `./install.sh --reset-settings` (Windows: `install.bat -ResetSettings`), or delete the folder
  `Settings/defgenx.AtariST/` on the card.
* **Something is wrong after a crash:** *Core Settings → Cold Restart* restarts the ST from scratch.

* **Black screen, nothing happens:** `tos.img` is missing from `Assets/atarist/common/` or is not a raw
  192/256 KB image (exactly 196,608 or 262,144 bytes). Re-copy it from the release zip.
* **Bombs or a crash at boot:** the TOS doesn't match the machine, e.g. the 192 KB EmuTOS with
  *Machine = STE*. Use `tos.img` (256 KB EmuTOS) for that. See step 2.
* **A game refuses to run:** it may need Atari's original TOS rather than EmuTOS.
* **Disk not seen:** only `.st` images work; set the disk in *Floppy A* before booting a game that
  needs it, then use *Reset ST*.
* **Image off-centre in mono mode:** a known gap in this first version, see `docs/video.md`.
