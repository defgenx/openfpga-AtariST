#!/usr/bin/env python3
"""Boot a TOS image in the full-system simulation at every RAM size, then change RAM
via a cold restart (what the core does) and via a warm reset (the old bug), and check
the memory size and screen address TOS set up. Runs in parallel; ~3-5 min.

  run_ram_tests.py <tos.img>
"""
import concurrent.futures as cf
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MISTERY = HERE.parent.parent / "src/fpga/MiSTery"
SIZES = {0: 0x80000, 1: 0x100000, 2: 0x200000, 3: 0x400000, 4: 0x800000, 5: 0xE00000}
NAMES = {0: "512 KB", 1: "1 MB", 2: "2 MB", 3: "4 MB", 4: "8 MB", 5: "14 MB"}

tos = Path(sys.argv[1]).read_bytes()
if len(tos) not in (196608, 262144):
    sys.exit(f"{sys.argv[1]}: {len(tos)} bytes, need a raw 192 or 256 KB TOS")
base = int.from_bytes(tos[8:12], "big")
emutos = b"EmuTOS" in tos

run = HERE / "run"
run.mkdir(exist_ok=True)
(HERE / "rom").mkdir(exist_ok=True)
shutil.copy(MISTERY / "ikbd/rom/ikbd.hex", HERE / "rom/ikbd.hex")
for f in ("microrom.mem", "nanorom.mem"):
    shutil.copy(MISTERY / "fx68k" / f, run / f)
hexf = run / "tos.hex"
hexf.write_text("".join(f"{tos[i]:02x}{tos[i+1]:02x}\n" for i in range(0, len(tos), 2)))
# the model preloads at word $700000 (byte $E00000); a 192 KB TOS lives at $FC0000
start = "fc0000" if base == 0xFC0000 else "e00000"

# original TOS only sizes 2 banks x 2 MB: more than 4 MB is EmuTOS-only
sizes = list(SIZES) if emutos else [0, 1, 2, 3]
cases = [(f"boot {NAMES[m]}", [f"+mem={m}"], [SIZES[m]]) for m in sizes]
cases += [
    ("1 MB -> 4 MB, cold restart", ["+mem=1", "+cold=3"], [SIZES[1], SIZES[3]]),
    ("4 MB -> 512 KB, cold restart", ["+mem=3", "+cold=0"], [SIZES[3], SIZES[0]]),
    ("4 MB -> 512 KB, warm reset (old bug)", ["+mem=3", "+warm=0"], [SIZES[3], None]),
]


def run_case(case):
    name, args, expect = case
    out = subprocess.run([str(HERE / "obj/Vst_system_tb"), f"+tos=tos.hex", f"+tosbase={start}", "+ms=500", *args],
                         cwd=run, capture_output=True, text=True).stdout
    got = [int(x, 16) for x in re.findall(r"phystop=\$([0-9a-f]+) ", out)]
    scr = [int(x, 16) for x in re.findall(r"_v_bas_ad=\$([0-9a-f]+)", out)]
    panic = "PANIC" in out
    ok = not panic and len(got) == len(expect) and all(e is None or g == e for g, e in zip(got, expect))
    ok = ok and all(e is None or s == e - 0x8000 for s, e in zip(scr, expect))
    return name, ok, got, scr, panic


print(f"TOS: {'EmuTOS' if emutos else 'Atari TOS'} at ${base:06X}, {len(tos) // 1024} KB")
fails = 0
with cf.ThreadPoolExecutor(max_workers=len(cases)) as ex:
    for name, ok, got, scr, panic in ex.map(run_case, cases):
        warm_case = "old bug" in name
        status = "PASS" if ok else ("expected" if warm_case else "FAIL")
        detail = ", ".join(f"RAM ${g:06X} screen ${s:06X}" for g, s in zip(got, scr)) + (" PANIC" if panic else "")
        print(f"  {status:8} {name:42} {detail}")
        fails += not ok and not warm_case
print("PASS" if fails == 0 else f"FAIL: {fails}")
sys.exit(1 if fails else 0)
