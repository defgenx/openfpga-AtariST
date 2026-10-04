# Input

## Pocket pads

| Pad | Joystick mode (default)            | Mouse mode                  |
|-----|------------------------------------|-----------------------------|
| 1   | ST joystick port 1 (the game port) | D-pad moves the mouse       |
| 2   | ST port 0 (shared with the mouse)  | same                        |

Pad 1 buttons: A = fire (left click in mouse mode), B = fire 2 (right click in mouse mode),
X = Space, Y = Return. In mouse mode the pointer speeds up after the D-pad is held ~0.5 s.

The IKBD switches port 0 between mouse and joystick on activity, as on MiST.

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

An on-screen keyboard for handheld use; the STe's enhanced joypad ports beyond what pads 1/2 provide.
