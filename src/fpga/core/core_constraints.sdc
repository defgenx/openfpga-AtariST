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

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks "$PLL*"]

# SDRAM (AS4C32M16SB): sampled by the clk_96_sd copy driven on dram_clk
set_input_delay  -clock [get_clocks $CLK_96S] -max 6.4 [get_ports {dram_dq[*]}]
set_input_delay  -clock [get_clocks $CLK_96S] -min 3.2 [get_ports {dram_dq[*]}]
set_output_delay -clock [get_clocks $CLK_96S] -max 1.5 [get_ports {dram_dq[*] dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_output_delay -clock [get_clocks $CLK_96S] -min -0.8 [get_ports {dram_dq[*] dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_false_path -to [get_ports {dram_clk}]

# clk_96 <-> clk_32: the chipset hands data over on 8 MHz enables
set_multicycle_path -from [get_clocks $CLK_96] -to [get_clocks $CLK_32] -start -setup 2
set_multicycle_path -from [get_clocks $CLK_96] -to [get_clocks $CLK_32] -start -hold 1
set_multicycle_path -from [get_clocks $CLK_32] -to [get_clocks $CLK_96] -end -setup 2
set_multicycle_path -from [get_clocks $CLK_32] -to [get_clocks $CLK_96] -end -hold 1
set_multicycle_path -from [get_clocks $CLK_128] -to [get_clocks $CLK_32] -setup 2
set_multicycle_path -from [get_clocks $CLK_128] -to [get_clocks $CLK_32] -hold 1

set_multicycle_path -start -setup -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|microAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|microAddr[*]}] 1
set_multicycle_path -start -setup -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {ic|atarist|fx68k|Ir[*]}] -to [get_keepers {ic|atarist|fx68k|nanoAddr[*]}] 1

set_multicycle_path -from {ic|atarist|sdram|dout[*]} -to {ic|atarist|sdram|*} -setup 2
set_multicycle_path -from {ic|atarist|sdram|dout[*]} -to {ic|atarist|sdram|*} -hold 1
