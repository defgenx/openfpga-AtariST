// Simulation-only replacement for MiSTery's sdram.v: same chipset-side interface and
// cycle timing (state machine copied from sdram.v), but backed by an array instead of
// driving SDRAM pins. Word address -> mem[] linearly.

module sdram (
	inout  [15:0] sd_data, output [12:0] sd_addr, output [1:0] sd_dqm, output [1:0] sd_ba,
	output sd_cs, output sd_we, output sd_ras, output sd_cas,
	input init, input clk_96, input clk_8_en,
	input [15:0] din, output reg [63:0] dout64, output reg [15:0] dout,
	input [23:0] addr, input [1:0] ds, input req, input we,
	input rom_oe, input [23:0] rom_addr, output reg [15:0] rom_dout
);
	assign sd_data = 16'hzzzz;
	assign {sd_addr, sd_dqm, sd_ba} = 0;
	assign {sd_cs, sd_we, sd_ras, sd_cas} = 4'hf;

	reg [15:0] mem [0:(1<<23)-1];   // 16 MB
	initial begin
		string f;
		int base;
		base = 'h700000;
		if ($test$plusargs("tosbase=fc0000")) base = 'h7e0000;
		if ($value$plusargs("tos=%s", f)) $readmemh(f, mem, base);
	end

	localparam STATE_FIRST = 4'd0, STATE_CMD_CONT = 4'd2, STATE_READ = 4'd6, STATE_LAST = 4'd11;
	reg [3:0] t;
	reg clk_8_enD;
	always @(posedge clk_96) begin
		clk_8_enD <= clk_8_en;
		if (~clk_8_enD & clk_8_en) t <= 4'hA; else t <= t + 1'd1;
		if (t == STATE_LAST) t <= STATE_FIRST;
	end

	reg [7:0] rst = 8'h1f;
	always @(posedge clk_96 or posedge init)
		if (init) rst <= 8'h1f; else if (t == STATE_LAST && rst != 0) rst <= rst - 8'd1;

	reg [23:0] addr_latch;
	reg [15:0] din_latch;
	reg        req_latch, rom_port;
	reg  [1:0] burst_addr;
	wire [22:0] a = addr_latch[22:0];

	always @(posedge clk_96) if (rst == 0) begin
		if (t == STATE_FIRST) begin
			if (req) begin
				addr_latch <= addr; req_latch <= 1; din_latch <= din; rom_port <= 0; burst_addr <= addr[1:0];
			end else if (rom_oe && (addr_latch != rom_addr)) begin
				addr_latch <= rom_addr; req_latch <= 1; rom_port <= 1; burst_addr <= rom_addr[1:0];
			end else req_latch <= 0;
		end
		if (req_latch) begin
			// sdram.v samples we/ds live at the CAS slot
			if (t == STATE_CMD_CONT && we) begin
				if (ds[1]) mem[a][15:8] <= din_latch[15:8];
				if (ds[0]) mem[a][7:0]  <= din_latch[7:0];
			end
			if ((!we || rom_port) && t >= STATE_READ && t < STATE_READ + 4'd4) begin
				if (burst_addr == addr_latch[1:0]) begin
					if (rom_port) rom_dout <= mem[{a[22:2], burst_addr}]; else dout <= mem[{a[22:2], burst_addr}];
				end
				case (burst_addr)
					2'd0: dout64[15:0]  <= mem[{a[22:2], 2'd0}];
					2'd1: dout64[31:16] <= mem[{a[22:2], 2'd1}];
					2'd2: dout64[47:32] <= mem[{a[22:2], 2'd2}];
					2'd3: dout64[63:48] <= mem[{a[22:2], 2'd3}];
				endcase
				burst_addr <= burst_addr + 2'd1;
			end
		end
	end

	// readers for the testbench (byte address)
	function automatic [31:0] peek_long(input [23:0] ba);
		peek_long = {mem[ba[23:1]], mem[ba[23:1] + 1]};
	endfunction
endmodule
