# Input

## Pocket pads

The handheld scheme follows the [Pocket Amiga core](https://github.com/Mazamars312/Analogue-Amiga):

| Button  | Mouse (default)   | Joystick              | Keys       | Keyboard shown      |
|---------|-------------------|-----------------------|------------|---------------------|
| D-pad   | move the pointer  | ST joystick (port 1)  | arrow keys | move the key cursor |
| A       | left click        | fire                  | Space      | press the key       |
| B       | right click       | fire 2                | Return     | close the keyboard  |
| X / Y   | Space / Return    | Space / Return        | Esc / Help | -                   |
| L / R   | left / right click| -                     | F1 / F2    | -                   |
| Select  | show the keyboard | show the keyboard     | show the keyboard | close        |
| Start   | -> joystick       | -> keys               | -> mouse   | -                   |

*Pad Mode* in the core settings picks the starting mode (mouse by default); Start cycles
mouse -> joystick -> keys, and a label shows the new mode for ~2 s. Keys mode sends real key presses
through the IKBD (up to all ten buttons at once), for games played on the keyboard. Pad 2 drives ST
port 0, which the IKBD shares with the mouse. A Dock analog controller's left stick also moves the
mouse, with L / R as the buttons.

### On-screen keyboard

Select opens a 16×5 keyboard at the bottom of the screen (`osk.sv`). Ctrl, Shift and Alt are sticky:
press them once, then the key; they release with it. Other keys are held for as long as A is held, so
games that need a key held down work. While the keyboard is shown the joystick is disconnected.

The layout is the table `LAYOUT` in `tools/gen_osk.py`, which generates `src/fpga/core/osk_layout.svh`
and the font ROM `osk_font.hex` (font8x8 by Daniel Hepper, public domain). Re-run it after editing:
`python3 tools/gen_osk.py tools/font8x8_basic.h`.

## 4-player adapter and STE joypads

Dock controllers on players 3 and 4 (when they are pads, not the keyboard or mouse) are the two extra
joysticks of the parallel-port 4-player adapter, wired as on MiST/MiSTer (Gauntlet II, Leatherneck…).
*STE Joypad Ports* in the menu presses the ST's F11, which MiSTery's IKBD uses to move pads 1 and 2 to
the STE enhanced ports; there A, B, X, Y and R are the Jaguar pad's A, B, C, Option and Pause. The ST
starts with the normal ports after every reset.

## Dock keyboard and mouse

The Dock reports a USB keyboard as player 3 and a USB mouse as player 4 (`cont3/4_key[31:28]` = 4 / 5):

* keyboard: `{cont3_joy, cont3_trig}` holds up to six HID usages in any order, `cont3_key[15:8]` the HID
  modifier byte;
* mouse: `cont4_key[15:0]` is a report counter (little-endian), `cont4_joy[15:0]` / `cont4_trig[15:0]`
  the relative X / Y motion (little-endian), `cont4_joy[18:16]` the buttons.

`hid_ps2` turns these into the PS/2 device streams MiSTery's IKBD (`ikbd/ps2.sv`) already decodes, so
the IKBD is used unchanged:

* Keyboard: the current key set is diffed against the keys already reported; each difference becomes a
  set-2 make or break code (with `E0` for extended keys). HID usages map to the PS/2 codes `ps2.sv`
  recognises, which in turn follow MiST's layout: Page Up = Help, Page Down = Undo, Print Screen = keypad
  `(`, End = keypad `)`, F11 toggles the STe joypad ports.
* Mouse: motion is accumulated and sent as IntelliMouse packets of at most ±6 counts. `ps2.sv`
  *replaces* its pending motion with each packet and drains it at ~2000 counts/s, so a packet must not
  carry more than one packet-time's worth of motion or the rest is lost.

`sim/hid_ps2_tb.sv` runs `hid_ps2` against MiSTery's `ps2.sv` and checks the resulting key matrix and
mouse quadrature counts.

## Not supported

Two simultaneous non-modifier keys from the on-screen keyboard; the STe's enhanced joypad ports beyond what pads 1/2 provide.
