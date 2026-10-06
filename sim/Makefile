# Simulation of the Pocket-specific modules (Icarus Verilog)
CORE = ../src/fpga/core
MISTERY = ../src/fpga/MiSTery

all: media media256 hid video osk

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

osk: osk_tb.vvp
	vvp -n osk_tb.vvp
	python3 ppm2png.py osk_frame.ppm osk_frame.png

osk_tb.vvp: osk_tb.sv $(CORE)/osk.sv $(CORE)/osk_layout.svh $(CORE)/st_video.sv
	iverilog -g2012 -I$(CORE) -o $@ osk_tb.sv $(CORE)/osk.sv $(CORE)/st_video.sv

# Full system: MiSTery's ST boots a TOS at every RAM size, plus RAM changes via cold restart.
#   make system                      uses the bundled EmuTOS
#   make system TOS=/path/tos104.img uses your own TOS image (192 or 256 KB)
TOS ?= ../dist/Assets/atarist/common/tos.img
SYSDIR = system
system: $(SYSDIR)/obj/Vst_system_tb
	python3 $(SYSDIR)/run_ram_tests.py "$(TOS)"

$(SYSDIR)/obj/Vst_system_tb: $(CORE)/st_video.sv $(SYSDIR)/st_system_tb.sv $(SYSDIR)/sdram_model.sv $(SYSDIR)/stubs.sv
	cd $(SYSDIR) && grep -v "^#" ../../src/fpga/core/mistery.qip | awk 'NF{print $$NF}' | sed 's/]//; s#^\.\./MiSTery/#../../src/fpga/MiSTery/#' \
		| grep -E "\.s?v$$" | grep -v -E "/sdram\.v$$|/tg68k\.v$$|altera_regs" > files.f
	cd $(SYSDIR) && for f in shifter_video_async hsyncgen hdegen vsyncgen vdegen vidcnt sndcnt modules; do echo ../../src/fpga/MiSTery/gstmcu/hdl/$$f.v >> files.f; done
	cd $(SYSDIR) && verilator --binary --timing --no-assert -j 8 -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
		-Wno-TIMESCALEMOD -Wno-BLKANDNBLK --Mdir obj --top-module st_system_tb \
		-I../../src/fpga/MiSTery/ikbd/hd63701 -I../../src/fpga/MiSTery/fx68k st_system_tb.sv sdram_model.sv stubs.sv ../../src/fpga/core/acsi_ctrl.sv ../../src/fpga/core/st_video.sv -f files.f

clean:
	rm -rf *.vvp *.vcd *.ppm *.png obj_* $(SYSDIR)/obj $(SYSDIR)/run $(SYSDIR)/rom $(SYSDIR)/files.f

.PHONY: all media media256 hid video osk system clean
