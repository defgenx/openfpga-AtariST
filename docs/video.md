# Video

The APF video clock is `clk_32` (32.084988 MHz), the ST's own master clock, so the shifter's output is
taken without any resampling.

* Colour (low and medium res): every other clock is marked `video_skip`, giving 640 samples per active
  line: low-res pixels (4 clocks) arrive twice, medium-res pixels (2 clocks) once.
* Mono: every clock is a pixel.

## Fixed windows

`st_video` cuts a fixed window out of every frame, positioned from the GLUE's `HSYNC_N`/`VSYNC_N`
falling edges, so the scaler always sees the same DE geometry even when software opens or moves the
borders. The machine standard is picked per frame from the previous frame's line count
(> 400 mono, > 290 PAL, otherwise NTSC).

Numbers measured with MiSTery's GSTMCU/Shifter testbench (`gstmcu/tb`), in `clk_32` cycles after the
hsync fall and lines after the vsync fall:

| Standard | Line   | Frame     | GLUE DE        | First/last pixel out | Blank (visible)  |
|----------|--------|-----------|----------------|----------------------|------------------|
| PAL      | 2048   | 313 lines | x 432–1711, y 66–265 | x 528–1807     | x 320–1999, y 28–310 |
| NTSC     | 2032   | 263 lines | x 416–1695, y 37–236 | x 512–1791     | x 304–1999, y 19–260 |
| Mono     | 896    | 501 lines | x 160–799, y 37–436  | not measured   | none             |

The shifter's pixels trail the GLUE's DE by 96 clocks in colour modes (fetching four bitplanes before the
first pixel can be shifted out). Windows are therefore placed on the measured pixel range, not on DE.

| Slot | Mode                | Window (x, y)              | Size    |
|------|---------------------|----------------------------|---------|
| 0    | PAL, borders        | 464–1871, 46–285           | 704×240 |
| 1    | PAL, no borders     | 528–1807, 66–265           | 640×200 |
| 2    | NTSC, borders       | 448–1855, 17–256           | 704×240 |
| 3    | NTSC, no borders    | 512–1791, 37–236           | 640×200 |
| 4    | Mono                | 246–885, 37–436            | 640×400 |

The slot is announced at the end of each line's active area (`video_rgb = {8'h00, slot, 13'h0}` on the
first clock with DE low), the convention used by other Pocket cores.

## Known gaps

* **Mono has no margin.** The first mono pixel leaves the shifter 246 clocks after the hsync fall
  (86 behind the GLUE's DE), measured by booting EmuTOS on an SM124 in `sim/system` (`+mono +ppm=`);
  the last one is at 885 of an 896-clock line, so the window is exactly the 640 pixels.
* **Medium res was only measured indirectly.** The testbench measured the same 96-clock lag for low and
  medium res; the structural estimate for medium res is smaller (~54 clocks). With borders shown (the
  default) the 32-pixel margins absorb either; with borders hidden, medium res may be shifted by up to
  ~20 pixels.
* Aspect ratios in `video.json` come from the PAL/NTSC pixel clocks (PAL samples ≈ 0.46:1, NTSC ≈ 0.38:1)
  and are untested on a real screen.
* Viking/SM194 hi-res is not supported (it needs a 128 MHz pixel clock).
