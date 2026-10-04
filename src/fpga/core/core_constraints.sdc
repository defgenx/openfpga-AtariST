#
# user core constraints
#
# pll_st outputs: general[0] clk_32, [1] clk_32_90, [2] clk_96, [3] clk_96_sd,
# [4] clk_128, [5] clk_2. They share one VCO, so they stay in one clock group.
# Multicycle paths are ported from MiSTery/mist/mist.sdc.
#

set PLL "ic|pll|altera_pll_i|general"
set CLK_32  "$PLL\[0\].gpll~PLL_OUTPUT_COUNTER|divclk"
set CLK_96  "$PLL\[2\].gpll~PLL_OUTPUT_COUNTER|divclk"
set CLK_96S "$PLL\[3\].gpll~PLL_OUTPUT_COUNTER|divclk"
set CLK_128 "$PLL\[4\].gpll~PLL_OUTPUT_COUNTER|divclk"


# SDRAM (AS4C32M16SB). dram_clk is driven by a DDIO register clocked by clk_96_sd,
# so it is a generated clock whose latency includes the same I/O path as the data.
create_generated_clock -name dram_clk_pin -source [get_pins "$CLK_96S"] [get_ports {dram_clk}]
set_input_delay  -clock dram_clk_pin -max 6.4 [get_ports {dram_dq[*]}]
set_input_delay  -clock dram_clk_pin -min 3.2 [get_ports {dram_dq[*]}]
set_output_delay -clock dram_clk_pin -max 1.5 [get_ports {dram_dq[*] dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_output_delay -clock dram_clk_pin -min -0.8 [get_ports {dram_dq[*] dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
# sdram.v expects CL2 data in sd_din on the clk_96 edge after the one matching the
# SDRAM's read edge, i.e. one period after the nearest edge the analyser would pick
set_multicycle_path -from [get_clocks dram_clk_pin] -to [get_clocks $CLK_96] -setup 2
set_multicycle_path -from [get_clocks dram_clk_pin] -to [get_clocks $CLK_96] -hold 1

# clk_96 <-> clk_32: the chipset hands data over on 8 MHz enables
set_multicycle_path -from [get_clocks $CLK_96] -to [get_clocks $CLK_32] -start -setup 2
set_multicycle_path -from [get_clocks $CLK_96] -to [get_clocks $CLK_32] -start -hold 1
set_multicycle_path -from [get_clocks $CLK_32] -to [get_clocks $CLK_96] -end -setup 2
set_multicycle_path -from [get_clocks $CLK_32] -to [get_clocks $CLK_96] -end -hold 1
set_multicycle_path -from [get_clocks $CLK_128] -to [get_clocks $CLK_32] -setup 2
set_multicycle_path -from [get_clocks $CLK_128] -to [get_clocks $CLK_32] -hold 1
# mist.sdc's clk[2] -> clk[0]: Viking video addresses (128 MHz) into the SDRAM controller (96 MHz).
# Live only with STE Turbo (STEroids enables the Viking logic).
set_multicycle_path -from [get_clocks $CLK_128] -to [get_clocks $CLK_96] -setup 2
set_multicycle_path -from [get_clocks $CLK_128] -to [get_clocks $CLK_96] -hold 1

set_multicycle_path -start -setup -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|microAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|microAddr[*]}] 1
set_multicycle_path -start -setup -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|nanoAddr[*]}] 1

set_multicycle_path -from {ic|atarist|sdram|dout[*]} -to {ic|atarist|sdram|*} -setup 2
set_multicycle_path -from {ic|atarist|sdram|dout[*]} -to {ic|atarist|sdram|*} -hold 1

# after dram_clk_pin exists
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks "$PLL* dram_clk_pin"]
