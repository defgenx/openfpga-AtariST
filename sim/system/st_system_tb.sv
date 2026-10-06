// Full-system test: MiSTery's atarist_sdram (FX68K, GSTMCU, shifter, MFP, IKBD...) boots a
// real TOS image from a behavioural SDRAM. Reports what TOS made of the machine.
//   +tos=<hex> +mem=<0..5> +model=<0 ST,1 STE,2 Mega STE,3 STE Turbo> +ms=<emulated milliseconds> [+warm=<mem2>]
// +mono selects the SM124; +vidlog logs every change in the frames st_video hands the scaler,
// +ppm=<ms> writes the first scaler frame after that time to frame.ppm.
// +warm reboots once with a different RAM size WITHOUT clearing low RAM (old v0.1.3 path);
// +cold does the same but clears $0-$FFF first (the v0.1.4 cold restart).
// +hook installs a reset handler (resvalid/resvector -> a bra.s * loop at $600) before the
// warm reset, as a game would; +warmclear zeroes $426-$42D in reset, as "Reset ST" does.
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
reg [1:0] model = 0;
reg       mono = 0;
reg  [7:0] acsi_en = 8'h00;
wire [31:0] system_ctrl = {7'd0, model, 5'd0, acsi_en, 1'b0, ~mono /* bit 8: colour monitor */, 2'b11 /*wp*/, 2'b00 /*68000*/, mem_sel, st_reset};

// ---- floppy A: served like st_media (ack, 512 bytes, drop ack) from a .st image ----
reg  [1:0]  fd_mounted = 0; reg [31:0] fd_size = 0;
wire [31:0] fd_lba; wire [1:0] fd_rd, fd_wr;
reg         fd_ack = 0, fd_strobe = 0; reg [8:0] fd_baddr = 0; reg [7:0] fd_dout = 0;
reg  [7:0]  floppy [0:737279];
integer     fd_reads = 0, fbi;
always @(posedge clk_32) begin
	if (|fd_rd && !fd_ack) begin
		fd_ack <= 1; fd_reads = fd_reads + 1;
		if ($test$plusargs("fdlog")) $display("  fdc read lba %0d (t=%0d ms)", fd_lba, $time / 1000000000);
		repeat (2000) @(posedge clk_32);              // APF read latency
		for (fbi = 0; fbi < 512; fbi = fbi + 1) begin
			fd_baddr <= fbi[8:0]; fd_dout <= floppy[fd_lba * 512 + fbi]; fd_strobe <= 1;
			@(posedge clk_32); fd_strobe <= 0; @(posedge clk_32);
		end
		fd_ack <= 0;
	end
end

// ---- ACSI hard disk: acsi_ctrl (as in core_top) + a disk image served like st_media ----
wire [7:0]  dio_status_in;  wire [3:0] dio_status_index;
wire        dio_ack_t, dio_in_t, dio_out_t; wire [7:0] dio_dma_status;
wire [15:0] dio_in_reg, dio_out_reg;
wire [1:0]  hd_rd, hd_wr; wire [31:0] hd_lba; wire [7:0] hd_din;
reg         hd_ack = 0; reg [8:0] hd_baddr = 0; reg [7:0] hd_bdout = 0; reg hd_bwr = 0;
reg  [7:0]  disk [0:(32*1024*1024)-1];
integer     disk_blocks = 0, hd_reads = 0, hd_writes = 0;
acsi_ctrl acsi (
	.clk(clk_32), .reset(st_reset),
	.status_in(dio_status_in), .status_index(dio_status_index),
	.dma_ack_t(dio_ack_t), .dma_status(dio_dma_status), .data_in_t(dio_in_t), .data_in_reg(dio_in_reg),
	.data_out_t(dio_out_t), .data_out_reg(dio_out_reg),
	.blocks0(disk_blocks), .blocks1(32'd0),
	.hd_rd(hd_rd), .hd_wr(hd_wr), .hd_lba(hd_lba), .hd_ack(hd_ack),
	.buff_addr(hd_baddr), .buff_dout(hd_bdout), .buff_wr(hd_bwr & hd_ack), .buff_din(hd_din)
);
integer bi;
always @(posedge clk_32) begin
	if (|hd_rd && !hd_ack) begin
		hd_ack <= 1; hd_reads = hd_reads + 1;
		repeat (50) @(posedge clk_32);
		for (bi = 0; bi < 512; bi = bi + 1) begin
			hd_baddr <= bi[8:0]; hd_bdout <= disk[hd_lba * 512 + bi]; hd_bwr <= 1;
			@(posedge clk_32); hd_bwr <= 0; @(posedge clk_32);
		end
		hd_ack <= 0;
	end else if (|hd_wr && !hd_ack) begin
		hd_ack <= 1; hd_writes = hd_writes + 1;
		for (bi = 0; bi < 512; bi = bi + 1) begin
			hd_baddr <= bi[8:0]; @(posedge clk_32); @(posedge clk_32); @(posedge clk_32);
			disk[hd_lba * 512 + bi] = hd_din;
		end
		hd_ack <= 0;
	end
end

wire [15:0] dq;
wire [3:0]  st_r, st_g, st_b;
wire        st_hs_n, st_vs_n, st_mono, st_blank_n;
atarist_sdram #(1'b0, 1'b1) atarist (
	.clk_96(clk_96), .clk_32(clk_32), .clk_128(clk_128), .clk_2(clk_2), .clk_mfp(mfp_en),
	.porb(porb), .system_ctrl(system_ctrl),
	.r(st_r), .g(st_g), .b(st_b), .hsync_n(st_hs_n), .vsync_n(st_vs_n), .hblank_n(), .vblank_n(), .monomode(st_mono), .blank_n(st_blank_n),
	.viking_active(), .viking_r(), .viking_g(), .viking_b(), .viking_hs(), .viking_vs(), .viking_hb(), .viking_vb(),
	.audio_mix_l(), .audio_mix_r(), .midi_out_strobe(), .midi_out(), .midi_rx(1'b1), .midi_tx(),
	.parallel_in_strobe(1'b1), .parallel_in(8'hff), .parallel_out_strobe(), .parallel_out(), .parallel_printer_busy(1'b1),
	.serial_redirect(1'b1), .serial_data_out_available(), .serial_strobe_out(1'b0), .serial_data_out(), .serial_status_out(),
	.serial_strobe_in(1'b0), .serial_data_in(8'h00), .uart_ctsb(1'b0), .uart_rtsb(), .uart_rx(1'b1), .uart_tx(),
	.data_in_strobe_rom(1'b0), .data_in_strobe_acsi(dio_in_t), .data_in_reg(dio_in_reg), .data_addr(23'h0), .data_download(1'b0),
	.data_out_strobe(dio_out_t), .data_out_reg(dio_out_reg), .dma_ack(dio_ack_t), .dma_status(dio_dma_status), .dma_nak(1'b0),
	.dma_status_in(dio_status_in), .dma_status_index(dio_status_index),
	.img_mounted(fd_mounted), .img_wp(2'b11), .img_size(fd_size), .sd_lba(fd_lba), .sd_rd(fd_rd), .sd_wr(fd_wr), .sd_ack(fd_ack),
	.sd_buff_addr(fd_baddr), .sd_dout(fd_dout), .sd_din(), .sd_dout_strobe(fd_strobe), .LED(),
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
	begin : marker
		integer a; reg found; found = 0;
		for (a = 'h800; a < 'h100000; a = a + 2)
			if (L(a) == 32'hEDCBA987 && L(a + 4) == 32'h9028384A) begin found = 1; $display("[%0s] AUTO\\MARKER.PRG ran: marker at $%06x", tag, a); end
		if (!found) $display("[%0s] AUTO\\MARKER.PRG marker not found", tag);
		$display("[%0s] floppy sector reads=%0d", tag, fd_reads);
	end
	$display("[%0s] _drvbits=%08x (C: %0s) acsi sector reads=%0d writes=%0d", tag, L(24'h4c2),
		L(24'h4c2) & 32'h4 ? "present" : "absent", hd_reads, hd_writes);
endtask

task run_ms(input integer ms);
	repeat (ms) repeat (32085) @(posedge clk_32);
endtask

integer ms = 400, m, m2, i;
string hdfile, fdfile;
initial begin
	if ($value$plusargs("mem=%d", m)) mem_sel = m[2:0];
	if ($value$plusargs("model=%d", m)) model = m[1:0];
	if ($test$plusargs("mono")) mono = 1;
	if ($value$plusargs("fd=%s", fdfile)) begin
		$readmemh(fdfile, floppy);
		fd_size = 737280;
		#5000000 fd_mounted = 2'b01; #500000 fd_mounted = 2'b00;   // after the FDC edge detector is defined
	end
	if ($value$plusargs("hd=%s", hdfile)) begin
		$readmemh(hdfile, disk);
		void'($value$plusargs("hdblocks=%d", disk_blocks));
		acsi_en = 8'h01;
	end
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
		if ($test$plusargs("hook")) begin
			atarist.sdram.mem['h213] = 16'h3141; atarist.sdram.mem['h214] = 16'h5926;   // resvalid
			atarist.sdram.mem['h215] = 16'h0000; atarist.sdram.mem['h216] = 16'h0600;   // resvector
			atarist.sdram.mem['h300] = 16'h60FE;                                        // bra.s *
		end
		st_reset = 1;
		mem_sel = m2[2:0];
		if ($test$plusargs("cold")) for (i = 0; i < 2048; i = i + 1) atarist.sdram.mem[i] = 16'h0000;
		if ($test$plusargs("warmclear")) for (i = 'h213; i < 'h217; i = i + 1) atarist.sdram.mem[i] = 16'h0000;
		repeat (100000) @(posedge clk_32);
		st_reset = 0;
		run_ms(ms);
		report($test$plusargs("cold") ? "cold reboot" : "warm reboot");
		$display("[warm reboot] cpu addr=$%06x resvalid=%08x", {atarist.fx68_a, 1'b0}, L(24'h426));
	end
	$finish;
end

// fdc probe: register writes and presence
reg fdc_sel_d = 0;
always @(posedge clk_32) if ($test$plusargs("fdprobe")) begin
	fdc_sel_d <= atarist.fdc1772.cpu_sel;
	if (atarist.fdc1772.cpu_sel && !fdc_sel_d && !atarist.fdc1772.cpu_rw)
		$display("  fdc write reg %0d = %02x  present=%b drive=%b (t=%0d ms)", atarist.fdc1772.cpu_addr, atarist.fdc1772.cpu_din,
			atarist.fdc1772.fdn_present[0], atarist.fdc1772.floppy_drive, $time / 1000000000);
end
always @(posedge fd_mounted[0]) $display("  img_mounted[0] rises, size %0d (t=%0d ns)", fd_size, $time / 1000);

// progress: CPU address every 50 ms
always begin
	run_ms(50);
	$display("  t=%0d ms  cpu addr=$%06x  phystop=$%06x", $time / 1000000000, {atarist.fx68_a, 1'b0}, L(24'h42e));
end

// ---- the core's scaler feed: st_video on the ST's real video outputs ----
wire [23:0] v_rgb; wire v_de, v_skip, v_hs, v_vs;
st_video stv (.clk(clk_32), .borders(1'b1), .r(st_r), .g(st_g), .b(st_b), .hsync_n(st_hs_n), .vsync_n(st_vs_n),
	.blank_n(st_blank_n), .monomode(st_mono), .video_rgb(v_rgb), .video_de(v_de), .video_skip(v_skip), .video_hs(v_hs), .video_vs(v_vs));
integer f_lines = 0, f_delines = 0, f_px = 0, f_pxmax = 0, f_pxmin = 99999, f_clk = 0, f_n = 0, l_px = 0;
reg [2:0] f_slot = 0; reg v_de_d = 0;
reg [127:0] last_sig = 0;
integer ppm_ms = -1, ppm_fd = 0, ppm_state = 0;
integer ppm_y = 0;
reg [7:0] ppm_buf [0:799][0:499][0:2];
integer px_x = 0, xx, yy;
initial void'($value$plusargs("ppm=%d", ppm_ms));
always @(posedge clk_32) begin
	f_clk = f_clk + 1;
	v_de_d <= v_de;
	if (v_de && !v_skip) begin
		if (ppm_state == 1 && px_x < 800 && ppm_y < 500) begin
			ppm_buf[px_x][ppm_y][0] = v_rgb[23:16]; ppm_buf[px_x][ppm_y][1] = v_rgb[15:8]; ppm_buf[px_x][ppm_y][2] = v_rgb[7:0];
		end
		l_px = l_px + 1; px_x = px_x + 1;
	end
	if (!v_de && v_de_d) begin   // end of an active line: slot word on the bus
		f_slot = v_rgb[15:13]; f_delines = f_delines + 1;
		if (l_px > f_pxmax) f_pxmax = l_px; if (l_px < f_pxmin) f_pxmin = l_px;
		l_px = 0; px_x = 0; ppm_y = ppm_y + 1;
	end
	if (v_hs) f_lines = f_lines + 1;
	if (v_vs) begin
		f_n = f_n + 1;
		if ($test$plusargs("vidlog") && {f_lines[15:0], f_delines[15:0], f_pxmin[15:0], f_pxmax[15:0], 5'd0, f_slot, f_clk[23:4]} != last_sig[107:0]) begin
			$display("  frame %0d t=%0d ms: %0d lines, %0d DE lines x %0d..%0d px, slot %0d, %0d clocks (%0d Hz)",
				f_n, $time / 1000000000, f_lines, f_delines, f_pxmin, f_pxmax, f_slot, f_clk, 32084988 / (f_clk > 0 ? f_clk : 1));
			last_sig[107:0] = {f_lines[15:0], f_delines[15:0], f_pxmin[15:0], f_pxmax[15:0], 5'd0, f_slot, f_clk[23:4]};
		end
		if (ppm_state == 1) begin
			ppm_fd = $fopen("frame.ppm", "w");
			$fwrite(ppm_fd, "P3\n%0d %0d\n255\n", f_pxmax, f_delines);
			for (yy = 0; yy < f_delines && yy < 500; yy = yy + 1)
				for (xx = 0; xx < f_pxmax && xx < 800; xx = xx + 1)
					$fwrite(ppm_fd, "%0d %0d %0d\n", ppm_buf[xx][yy][0], ppm_buf[xx][yy][1], ppm_buf[xx][yy][2]);
			$fclose(ppm_fd); ppm_state = 2;
			$display("  frame.ppm written (frame %0d, %0dx%0d)", f_n, f_pxmax, f_delines);
		end
		if (ppm_state == 0 && ppm_ms >= 0 && $time / 1000000000 >= ppm_ms) ppm_state = 1;
		f_lines = 0; f_delines = 0; f_pxmax = 0; f_pxmin = 99999; f_clk = 0; ppm_y = 0;
	end
end

endmodule
