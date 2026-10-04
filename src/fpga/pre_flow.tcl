# Quartus pre-flow script (runs in the project directory).
# MiSTery's $readmem paths are relative to the project directory of its MiST
# build (mist/), so its ROM images are copied to where those paths point.
file copy -force MiSTery/fx68k/microrom.mem microrom.mem
file copy -force MiSTery/fx68k/nanorom.mem nanorom.mem
file mkdir ../ikbd/rom
file copy -force MiSTery/ikbd/rom/ikbd.hex ../ikbd/rom/ikbd.hex

source apf/build_id_gen.tcl
