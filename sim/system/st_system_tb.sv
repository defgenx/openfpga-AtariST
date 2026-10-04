// Full-system test: MiSTery's atarist_sdram (FX68K, GSTMCU, shifter, MFP, IKBD...) boots a
// real TOS image from a behavioural SDRAM. Reports what TOS made of the machine.
//   +tos=<hex> +mem=<0..5> +ms=<emulated milliseconds> [+warm=<mem2>]
// +warm reboots once with a different RAM size WITHOUT clearing low RAM (old v0.1.3 path);
// +cold does the same but clears $0-$FFF first (the v0.1.4 cold restart).
`timescale 1ps/1ps

module st_system_tb;

reg base = 0;
always #1302 base = ~base;           // 384 MHz
reg [7:0] div = 0;
reg clk_32 = 0, clk_96 = 0, clk_128 = 0, clk_2 = 0;
always @(posedge base) begin
	div <= (div == 191) ? 0 : div + 1;
	clk_96  <= div[1];               // /4
	clk_32  <= (div % 12) < 6;       // /12
	clk_128 <= (div % 3) == 0;       // /3
	clk_2   <= div < 96;             // /192
end

reg [31:0] mfp_acc = 0; reg mfp_en = 0;
always @(posedge clk_32) begin
	mfp_en <= 0;
	if (mfp_acc < 32084988) mfp_acc <= mfp_acc + 2457600;
	else begin mfp_acc <= mfp_acc - 32084988 + 2457600; mfp_en <= 1; end
end

reg porb = 0;
reg st_reset = 1;
reg [2:0] mem_sel = 1;
wire [31:0] system_ctrl = {23'd0, 1'b0 /*mono*/, 2'b11 /*wp*/, 2'b00 /*68000*/, mem_sel, st_reset};

wire [15:0] dq;
atarist_sdram #(1'b0, 1'b1) atarist (
	.clk_96(clk_96), .clk_32(clk_32), .clk_128(clk_128), .clk_2(clk_2), .clk_mfp(mfp_en),
	.porb(porb), .system_ctrl(system_ctrl),
	.r(), .g(), .b(), .hsync_n(), .vsync_n(), .hblank_n(), .vblank_n(), .monomode(), .blank_n(),
	.viking_active(), .viking_r(), .viking_g(), .viking_b(), .viking_hs(), .viking_vs(), .viking_hb(), .viking_vb(),
	.audio_mix_l(), .audio_mix_r(), .midi_out_strobe(), .midi_out(), .midi_rx(1'b1), .midi_tx(),
	.parallel_in_strobe(1'b1), .parallel_in(8'hff), .parallel_out_strobe(), .parallel_out(), .parallel_printer_busy(1'b1),
	.serial_redirect(1'b1), .serial_data_out_available(), .serial_strobe_out(1'b0), .serial_data_out(), .serial_status_out(),
	.serial_strobe_in(1'b0), .serial_data_in(8'h00), .uart_ctsb(1'b0), .uart_rtsb(), .uart_rx(1'b1), .uart_tx(),
	.data_in_strobe_rom(1'b0), .data_in_strobe_acsi(1'b0), .data_in_reg(16'h0), .data_addr(23'h0), .data_download(1'b0),
	.data_out_strobe(1'b0), .data_out_reg(), .dma_ack(1'b0), .dma_status(8'h0), .dma_nak(1'b0), .dma_status_in(), .dma_status_index(4'd0),
	.img_mounted(2'b00), .img_wp(2'b11), .img_size(32'd0), .sd_lba(), .sd_rd(), .sd_wr(), .sd_ack(1'b0),
	.sd_buff_addr(9'd0), .sd_dout(8'h0), .sd_din(), .sd_dout_strobe(1'b0), .LED(),
	.eth_status(), .eth_mac_begin(1'b0), .eth_mac_strobe(1'b0), .eth_mac_byte(8'h0), .eth_tx_read_begin(1'b0),
	.eth_tx_read_strobe(1'b0), .eth_tx_read_byte(), .eth_rx_write_begin(1'b0), .eth_rx_write_strobe(1'b0), .eth_rx_write_byte(8'h0),
	.ps2_kbd_clk(1'b1), .ps2_kbd_data(1'b1), .ps2_mouse_clk(1'b1), .ps2_mouse_data(1'b1),
	.joy0(16'd0), .joy1(16'd0), .rtc(64'd0),
	.SDRAM_DQ(dq), .SDRAM_A(), .SDRAM_DQML(), .SDRAM_DQMH(), .SDRAM_nWE(), .SDRAM_nCAS(), .SDRAM_nRAS(), .SDRAM_nCS(), .SDRAM_BA()
);

function automatic [31:0] L(input [23:0] a); L = atarist.sdram.peek_long(a); endfunction
function automatic [15:0] W(input [23:0] a); W = atarist.sdram.mem[a[23:1]]; endfunction

task report(input [8*12-1:0] tag);
	$display("[%0s] mem_sel=%0d phystop=$%06x _memtop=$%06x _v_bas_ad=$%06x memvalid=%08x memcntlr=$%02x",
		tag, mem_sel, L(24'h42e), L(24'h436), L(24'h44e), L(24'h420), W(24'h424) & 16'hff);
	if (L(24'h380) == 32'h12345678)
		$display("[%0s] PANIC: exception %0d, SR=%04x PC=%08x", tag, L(24'h3c4), W(24'h3cc), {W(24'h3ce), W(24'h3d0)});
	else
		$display("[%0s] no panic recorded", tag);
endtask

task run_ms(input integer ms);
	repeat (ms) repeat (32085) @(posedge clk_32);
endtask

integer ms = 400, m, m2, i;
initial begin
	if ($value$plusargs("mem=%d", m)) mem_sel = m[2:0];
	// set by the TOS download on hardware; the model preloads memory instead
	if ($test$plusargs("tosbase=fc0000")) atarist.tos192k = 1'b1;
	void'($value$plusargs("ms=%d", ms));
	repeat (2000) @(posedge clk_32);
	porb = 1;
	repeat (100000) @(posedge clk_32);     // sdram model init, GSTMCU running
	st_reset = 0;
	run_ms(ms);
	report("boot");

	if ($value$plusargs("warm=%d", m2) || $value$plusargs("cold=%d", m2)) begin
		st_reset = 1;
		mem_sel = m2[2:0];
		if ($test$plusargs("cold")) for (i = 0; i < 2048; i = i + 1) atarist.sdram.mem[i] = 16'h0000;
		repeat (100000) @(posedge clk_32);
		st_reset = 0;
		run_ms(ms);
		report($test$plusargs("cold") ? "cold reboot" : "warm reboot");
	end
	$finish;
end

// progress: CPU address every 50 ms
always begin
	run_ms(50);
	$display("  t=%0d ms  cpu addr=$%06x  phystop=$%06x", $time / 1000000000, {atarist.fx68_a, 1'b0}, L(24'h42e));
end

endmodule
