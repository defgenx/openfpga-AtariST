# Simulation of the Pocket-specific modules (Icarus Verilog)
CORE = ../src/fpga/core
MISTERY = ../src/fpga/MiSTery

all: media media256 hid video

media: st_media_tb.vvp
	vvp -n st_media_tb.vvp

st_media_tb.vvp: st_media_tb.sv $(CORE)/st_media.sv
	iverilog -g2012 -o $@ st_media_tb.sv $(CORE)/st_media.sv

# 256 KB TOS at $$E00000
media256: st_media_tb256.vvp
	vvp -n st_media_tb256.vvp

st_media_tb256.vvp: st_media_tb.sv $(CORE)/st_media.sv
	iverilog -g2012 -DTOS256 -o $@ st_media_tb.sv $(CORE)/st_media.sv

# Verilator: MiSTery's ps2.sv uses signals before declaring them, which Icarus rejects
hid: obj_hid/Vhid_ps2_tb
	obj_hid/Vhid_ps2_tb

obj_hid/Vhid_ps2_tb: hid_ps2_tb.sv $(CORE)/hid_ps2.sv $(MISTERY)/ikbd/ps2.sv
	verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style --Mdir obj_hid --top-module hid_ps2_tb hid_ps2_tb.sv $(CORE)/hid_ps2.sv $(MISTERY)/ikbd/ps2.sv

video: st_video_tb.vvp
	vvp -n st_video_tb.vvp

st_video_tb.vvp: st_video_tb.sv $(CORE)/st_video.sv
	iverilog -g2012 -o $@ st_video_tb.sv $(CORE)/st_video.sv

clean:
	rm -rf *.vvp *.vcd obj_*

.PHONY: all media media256 hid video clean
