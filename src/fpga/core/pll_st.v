//
// pll_st.v - Atari ST clocks from the Pocket's 74.25 MHz reference
//
// MiSTery needs clk_32/96/128/2 phase-related (one VCO): 32.084988 MHz is the
// PAL ST master clock, the rest are x3, x4 and /16 of it.
//

`timescale 1ns/10ps
module pll_st (
	input  wire refclk,   // 74.25 MHz
	input  wire rst,
	output wire clk_32,
	output wire clk_32_90,  // APF video_rgb_clock_90
	output wire clk_96,
	output wire clk_96_sd,  // SDRAM pin clock, leads clk_96 by ~2 ns
	output wire clk_128,
	output wire clk_2,
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("74.25 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(6),
		.output_clock_frequency0("32.084988 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.output_clock_frequency1("32.084988 MHz"),
		.phase_shift1("7792 ps"),
		.duty_cycle1(50),
		.output_clock_frequency2("96.254964 MHz"),
		.phase_shift2("0 ps"),
		.duty_cycle2(50),
		.output_clock_frequency3("96.254964 MHz"),
		.phase_shift3("8441 ps"),   // 52 VCO steps (1/8 of the 770.04 MHz VCO period each)
		.duty_cycle3(50),
		.output_clock_frequency4("128.339952 MHz"),
		.phase_shift4("0 ps"),
		.duty_cycle4(50),
		.output_clock_frequency5("2.005312 MHz"),
		.phase_shift5("0 ps"),
		.duty_cycle5(50),
		.output_clock_frequency6("0 MHz"),
		.phase_shift6("0 ps"),
		.duty_cycle6(50),
		.output_clock_frequency7("0 MHz"),
		.phase_shift7("0 ps"),
		.duty_cycle7(50),
		.output_clock_frequency8("0 MHz"),
		.phase_shift8("0 ps"),
		.duty_cycle8(50),
		.output_clock_frequency9("0 MHz"),
		.phase_shift9("0 ps"),
		.duty_cycle9(50),
		.output_clock_frequency10("0 MHz"),
		.phase_shift10("0 ps"),
		.duty_cycle10(50),
		.output_clock_frequency11("0 MHz"),
		.phase_shift11("0 ps"),
		.duty_cycle11(50),
		.output_clock_frequency12("0 MHz"),
		.phase_shift12("0 ps"),
		.duty_cycle12(50),
		.output_clock_frequency13("0 MHz"),
		.phase_shift13("0 ps"),
		.duty_cycle13(50),
		.output_clock_frequency14("0 MHz"),
		.phase_shift14("0 ps"),
		.duty_cycle14(50),
		.output_clock_frequency15("0 MHz"),
		.phase_shift15("0 ps"),
		.duty_cycle15(50),
		.output_clock_frequency16("0 MHz"),
		.phase_shift16("0 ps"),
		.duty_cycle16(50),
		.output_clock_frequency17("0 MHz"),
		.phase_shift17("0 ps"),
		.duty_cycle17(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst      (rst),
		.outclk   ({clk_2, clk_128, clk_96_sd, clk_96, clk_32_90, clk_32}),
		.locked   (locked),
		.fboutclk (),
		.fbclk    (1'b0),
		.refclk   (refclk)
	);

endmodule
