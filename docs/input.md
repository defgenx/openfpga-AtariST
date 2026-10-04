# Input

## Pocket pads

The handheld scheme follows the [Pocket Amiga core](https://github.com/Mazamars312/Analogue-Amiga):

| Button  | Joystick mode (default) | Mouse mode               | Keyboard shown          |
|---------|-------------------------|--------------------------|-------------------------|
| D-pad   | ST joystick (port 1)    | move the pointer         | move the key cursor     |
| A       | fire                    | left click               | press the key           |
| B       | fire 2                  | right click              | close the keyboard      |
| X / Y   | Space / Return          | Space / Return           | -                       |
| L / R   | -                       | left / right click       | -                       |
| Select  | show the keyboard       | show the keyboard        | close the keyboard      |
| Start   | switch to mouse mode    | switch to joystick mode  | -                       |

*Pad Mode* in the core settings picks which mode the core starts in; Start flips it. In mouse mode the
pointer speeds up after the D-pad is held ~0.5 s. Pad 2 drives ST port 0, which the IKBD shares with the
mouse (it switches on activity, as on MiST). A Dock analog controller's left stick also moves the mouse,
with L / R as the buttons.

### On-screen keyboard

Select opens a 16×5 keyboard at the bottom of the screen (`osk.sv`). Ctrl, Shift and Alt are sticky:
press them once, then the key; they release with it. Other keys are held for as long as A is held, so
games that need a key held down work. While the keyboard is shown the joystick is disconnected.

The layout is the table `LAYOUT` in `tools/gen_osk.py`, which generates `src/fpga/core/osk_layout.svh`
and the font ROM `osk_font.hex` (font8x8 by Daniel Hepper, public domain). Re-run it after editing:
`python3 tools/gen_osk.py tools/font8x8_basic.h`.

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
