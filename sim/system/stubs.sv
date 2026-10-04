// Simulation-only stand-ins for MiSTery parts written in VHDL (Verilator reads Verilog only).
// YM2149: register file and I/O ports only (no sound). TG68K: unused (68000 = FX68K).

module YM2149 #(parameter MIXER_VOLTABLE = 1'b0, parameter IO_OUT_READ_IN = 1'b1) (
	input  [7:0] I_DA, output [7:0] O_DA, output O_DA_OE_L,
	input  I_BDIR, input I_BC1, input I_STEREO,
	output [9:0] O_AUDIO_L, output [9:0] O_AUDIO_R,
	input  [7:0] I_IOA, output [7:0] O_IOA, input [7:0] I_IOB, output [7:0] O_IOB,
	input  ENA, input RESET_L, input CLK
);
	reg [7:0] regs[16];
	reg [3:0] sel;
	integer i;
	always @(posedge CLK) begin
		if (!RESET_L) begin for (i = 0; i < 16; i = i + 1) regs[i] <= 8'h00; sel <= 0; end
		else begin
			if (I_BDIR &  I_BC1) sel <= I_DA[3:0];
			if (I_BDIR & ~I_BC1) regs[sel] <= I_DA;
		end
	end
	assign O_DA = (sel == 4'd14) ? (regs[7][6] ? regs[14] : I_IOA) : (sel == 4'd15) ? (regs[7][7] ? regs[15] : I_IOB) : regs[sel];
	assign O_DA_OE_L = ~(~I_BDIR & I_BC1);
	assign O_IOA = regs[14];
	assign O_IOB = regs[15];
	assign O_AUDIO_L = 10'h200;
	assign O_AUDIO_R = 10'h200;
endmodule

module tg68k (
	input clk, input reset, input phi1, input phi2, input [1:0] cpu,
	input dtack_n, output rw_n, output as_n, output uds_n, output lds_n, output [2:0] fc, output reset_n,
	output reg E, output vma_n, input vpa_n, input br_n, output bg_n, input bgack_n,
	input [2:0] ipl, input berr, input [15:0] din, output [15:0] dout, output reg [31:0] addr
);
	assign {rw_n, as_n, uds_n, lds_n, reset_n, vma_n, bg_n} = 7'h7f;
	assign fc = 3'b000;
	assign dout = 16'h0000;
	initial begin E = 0; addr = 0; end
endmodule
