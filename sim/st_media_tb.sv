// st_media testbench: models APF target commands and the FDC sector interface.
// Run: make -C sim media
`timescale 1ns/1ps

module st_media_tb;

reg clk_74a = 0, clk_32 = 0;
always #6.734 clk_74a = ~clk_74a;
always #15.58 clk_32 = ~clk_32;

// ---------------- files ----------------
`ifdef TOS256
localparam TOS_SIZE = 262144;
localparam [23:0] TOS_BASE = 24'hE00000;
`else
localparam TOS_SIZE = 196608;
localparam [23:0] TOS_BASE = 24'hFC0000;
`endif
localparam FDA_SIZE = 737280;
localparam HD_SIZE = 1048576;
localparam CART_SIZE = 131076;   // .stc with a 4-byte header
reg [7:0] cart [0:CART_SIZE-1];
reg [7:0] hd [0:HD_SIZE-1];
reg [7:0] tos [0:TOS_SIZE-1];
reg [7:0] fda [0:FDA_SIZE-1];
integer i;
initial begin
	for (i = 0; i < TOS_SIZE; i = i + 1) tos[i] = (i * 7 + (i >> 8)) & 8'hff;
	{tos[8], tos[9], tos[10], tos[11]} = {8'h00, TOS_BASE};   // os_base
`ifdef TOS256
	{tos[2], tos[3]} = 16'h0206;
	{tos['h2C], tos['h2D], tos['h2E], tos['h2F]} = "ETOS";
`endif
	for (i = 0; i < FDA_SIZE; i = i + 1) fda[i] = (i * 13 + (i >> 9)) & 8'hff;
	for (i = 0; i < HD_SIZE; i = i + 1) hd[i] = (i * 29 + (i >> 9)) & 8'hff;
	for (i = 0; i < CART_SIZE; i = i + 1) cart[i] = (i * 3 + 7) & 8'hff;
end

// ---------------- DUT ----------------
reg  [31:0] bridge_addr = 0;
reg         bridge_wr = 0;
reg  [31:0] bridge_wr_data = 0;
wire [31:0] bridge_rd_data;
wire        t_read, t_write;
wire [15:0] t_id;
wire [31:0] t_off, t_baddr, t_len;
reg         t_done = 0;
reg   [2:0] t_err = 0;
integer     fail_cmds = 0;     // the next N commands answer with an error and no data
integer     cmds = 0;
reg         warm_req = 0;
wire        warm_busy;
reg         ds_update = 0;
reg  [15:0] ds_update_id = 0;
reg  [31:0] ds_update_size = 0;
reg         allcomplete = 0;
reg         cold_req = 0;
wire        load_cart;
wire [11:0] load_pct;
reg  [11:0] pct_seen_max = 0;
wire  [9:0] dt_addr;
reg  [31:0] dt_q;

wire        tos_done, data_download, data_in_strobe;
wire [23:1] data_addr;
wire [15:0] data_in_reg;
wire  [1:0] img_mounted;
wire [31:0] img_size;
reg  [31:0] sd_lba = 0;
reg   [1:0] sd_rd = 0, sd_wr = 0;
wire        sd_ack, sd_dout_strobe;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_dout;
reg   [7:0] sd_din;

reg  [1:0] hd_rd = 0, hd_wr = 0; reg [31:0] hd_lba = 0; wire hd_ack; reg [7:0] hd_din; wire [31:0] hd_size0;
st_media dut (
	.clk_74a(clk_74a), .clk_32(clk_32),
	.bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data), .bridge_rd_data(bridge_rd_data),
	.target_dataslot_read(t_read), .target_dataslot_write(t_write), .target_dataslot_id(t_id),
	.target_dataslot_slotoffset(t_off), .target_dataslot_bridgeaddr(t_baddr), .target_dataslot_length(t_len),
	.target_dataslot_done(t_done), .target_dataslot_err(t_err),
	.dataslot_update(ds_update), .dataslot_update_id(ds_update_id), .dataslot_update_size(ds_update_size),
	.dataslot_allcomplete(allcomplete), .datatable_addr(dt_addr), .datatable_q(dt_q),
	.cold_req(cold_req), .warm_req(warm_req), .warm_busy(warm_busy), .tos_done(tos_done), .load_cart(load_cart), .load_pct(load_pct), .data_download(data_download), .data_addr(data_addr), .data_in_reg(data_in_reg), .data_in_strobe(data_in_strobe),
	.img_mounted(img_mounted), .img_size(img_size), .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_dout(sd_dout), .sd_dout_strobe(sd_dout_strobe), .sd_din(sd_din),
	.hd_rd(hd_rd), .hd_wr(hd_wr), .hd_lba(hd_lba), .hd_ack(hd_ack), .hd_din(hd_din), .hd_size0(hd_size0), .hd_size1()
);
always @(posedge clk_32) if (data_download && !load_cart && load_pct > pct_seen_max) pct_seen_max <= load_pct;
reg  [7:0] hd_buf [0:511];
always @(posedge clk_32) begin
	if (sd_dout_strobe & hd_ack) hd_buf[sd_buff_addr] <= sd_dout;
	hd_din <= hd_buf[sd_buff_addr];
	if (hd_ack) begin hd_rd <= 0; hd_wr <= 0; end
end

// ---------------- APF datatable: 2-cycle registered read ----------------
reg [31:0] dt_mem [0:255];
reg [31:0] dt_q1;
initial begin
	for (i = 0; i < 256; i = i + 1) dt_mem[i] = 0;
	dt_mem[0] = 0; dt_mem[1] = TOS_SIZE;
	dt_mem[2] = 1; dt_mem[3] = FDA_SIZE;
	dt_mem[4] = 2; dt_mem[5] = 0;
	dt_mem[6] = 3; dt_mem[7] = HD_SIZE;
	dt_mem[8] = 5; dt_mem[9] = CART_SIZE;
end
always @(posedge clk_74a) begin dt_q1 <= dt_mem[dt_addr]; dt_q <= dt_q1; end

// ---------------- APF target command model ----------------
reg t_read_d = 0, t_write_d = 0;
reg op_read;
integer w, base;
reg [31:0] word;
always @(posedge clk_74a) begin t_read_d <= t_read; t_write_d <= t_write; end

task apf_cycle; @(posedge clk_74a); endtask

initial begin : apf
	forever begin
		@(posedge clk_74a);
		if ((t_read & ~t_read_d) | (t_write & ~t_write_d)) begin
			op_read = t_read;
			// bridge clears done when it starts the command
			repeat (3) apf_cycle; t_done <= 0;
			repeat (40) apf_cycle;
			cmds = cmds + 1;
			if (fail_cmds > 0) begin
				fail_cmds = fail_cmds - 1;
				t_err <= 3'd2;
			end else if (op_read) begin
				t_err <= 3'd0;
				for (w = 0; w < t_len / 4; w = w + 1) begin
					base = t_off + w * 4;
					if (t_id == 0) word = {tos[base], tos[base+1], tos[base+2], tos[base+3]};
					else if (t_id == 3) word = {hd[base], hd[base+1], hd[base+2], hd[base+3]};
					else if (t_id == 5) word = {cart[base], cart[base+1], cart[base+2], cart[base+3]};
					else           word = {fda[base], fda[base+1], fda[base+2], fda[base+3]};
					bridge_addr <= t_baddr + w * 4; bridge_wr_data <= word; bridge_wr <= 1;
					apf_cycle; bridge_wr <= 0;
					repeat (2) apf_cycle;    // APF writes are not back to back
				end
			end else begin
				t_err <= 3'd0;
				for (w = 0; w < t_len / 4; w = w + 1) begin
					bridge_addr <= t_baddr + w * 4;
					repeat (3) apf_cycle;
					base = t_off + w * 4;
					if (t_id == 3) {hd[base], hd[base+1], hd[base+2], hd[base+3]} = bridge_rd_data;
					else {fda[base], fda[base+1], fda[base+2], fda[base+3]} = bridge_rd_data;
				end
			end
			repeat (20) apf_cycle;
			t_done <= 1;
		end
	end
end

// ---------------- FDC buffer model (registered read, like fdc1772_dpram) ----------------
reg [7:0] fdc_buf [0:511];
always @(posedge clk_32) begin
	if (sd_dout_strobe & sd_ack) fdc_buf[sd_buff_addr] <= sd_dout;
	sd_din <= fdc_buf[sd_buff_addr];
end
// sd_rd/sd_wr are cleared by the FDC once sd_ack rises
always @(posedge clk_32) if (sd_ack) begin sd_rd <= 0; sd_wr <= 0; end

// ---------------- checks ----------------
integer errors = 0;
integer words_seen = 0;
integer clear_seen = 0;
integer k2;
integer warm_seen = 0;
reg strobe_d = 0;
reg in_warm = 0;
reg [23:0] exp_byte_addr;
always @(posedge clk_32) begin
	strobe_d <= data_in_strobe;
	if (data_in_strobe != strobe_d && in_warm) begin
		if ({data_addr, 1'b0} != 24'h426 + warm_seen * 2 || data_in_reg != 16'h0000 || !warm_busy) begin
			$display("warm clear mismatch word %0d: addr %06x data %04x busy %b", warm_seen, {data_addr, 1'b0}, data_in_reg, warm_busy);
			errors = errors + 1;
		end
		warm_seen = warm_seen + 1;
	end else if (data_in_strobe != strobe_d && clear_seen < 2048) begin
		if ({data_addr, 1'b0} != clear_seen * 2 || data_in_reg != 16'h0000) begin
			$display("clear mismatch word %0d: addr %06x data %04x", clear_seen, {data_addr, 1'b0}, data_in_reg);
			errors = errors + 1;
		end
		clear_seen = clear_seen + 1;
	end else if (data_in_strobe != strobe_d && words_seen >= TOS_SIZE / 2) begin
		k2 = words_seen - TOS_SIZE / 2;
		if ({data_addr, 1'b0} != 24'hFA0000 + k2 * 2 || data_in_reg != {cart[4 + k2*2], cart[5 + k2*2]}) begin
			if (errors < 10) $display("cart mismatch word %0d: addr %06x data %04x", k2, {data_addr, 1'b0}, data_in_reg);
			errors = errors + 1;
		end
		words_seen = words_seen + 1;
	end else if (data_in_strobe != strobe_d) begin
		exp_byte_addr = TOS_BASE + words_seen * 2;
		if ({data_addr, 1'b0} != exp_byte_addr || data_in_reg != {tos[words_seen*2], tos[words_seen*2+1]}) begin
			if (errors < 10) $display("TOS mismatch word %0d: addr %06x data %04x, expected %06x %02x%02x",
				words_seen, {data_addr, 1'b0}, data_in_reg, exp_byte_addr, tos[words_seen*2], tos[words_seen*2+1]);
			errors = errors + 1;
		end
		if (!data_download) begin $display("strobe outside download"); errors = errors + 1; end
		words_seen = words_seen + 1;
	end
end

reg mounted_a = 0;
always @(posedge clk_32) if (img_mounted[0] && !mounted_a) begin
	if (img_size != FDA_SIZE) begin $display("mount size %0d", img_size); errors = errors + 1; end
	mounted_a = 1;
end

integer k;
initial begin
	repeat (50) @(posedge clk_74a);
	allcomplete <= 1; @(posedge clk_74a); allcomplete <= 0;

	wait (tos_done);
	$display("low RAM cleared: %0d words; TOS loaded: %0d words at t=%0t", clear_seen, words_seen, $time);
	$display("loading screen: TOS reached %0x%%, cartridge ended at %0x%%", pct_seen_max, load_pct);
	@(posedge clk_32); @(posedge clk_32);
	if (pct_seen_max < 12'h090 || load_pct != 12'h100) begin $display("progress did not reach 100%%"); errors = errors + 1; end
	if (clear_seen != 2048) begin $display("expected 2048 cleared words"); errors = errors + 1; end
	if (words_seen != TOS_SIZE / 2 + 65536) begin $display("expected %0d TOS + 65536 cartridge words, got %0d", TOS_SIZE/2, words_seen); errors = errors + 1; end
	repeat (100) @(posedge clk_32);
	if (!mounted_a) begin $display("drive A not mounted"); errors = errors + 1; end

	// sector read, drive A, LBA 5
	@(posedge clk_32); sd_lba <= 5; sd_rd <= 2'b01;
	wait (sd_ack); wait (!sd_ack);
	for (k = 0; k < 512; k = k + 1) if (fdc_buf[k] !== fda[5*512 + k]) begin
		if (errors < 10) $display("read mismatch byte %0d: %02x expected %02x", k, fdc_buf[k], fda[5*512+k]);
		errors = errors + 1;
	end
	$display("sector read done");

	// APF answers twice with an error: the read is sent again and the data is still right
	cmds = 0; fail_cmds = 2;
	for (k = 0; k < 512; k = k + 1) fdc_buf[k] = 8'h00;
	@(posedge clk_32); sd_lba <= 9; sd_rd <= 2'b01;
	wait (sd_ack); wait (!sd_ack);
	for (k = 0; k < 512; k = k + 1) if (fdc_buf[k] !== fda[9*512 + k]) begin
		if (errors < 10) $display("retried read mismatch byte %0d: %02x expected %02x", k, fdc_buf[k], fda[9*512+k]);
		errors = errors + 1;
	end
	if (cmds != 3) begin $display("expected 3 commands for the retried read, got %0d", cmds); errors = errors + 1; end
	$display("sector read after 2 APF errors: %0d commands", cmds);

	// sector write, drive A, LBA 7
	for (k = 0; k < 512; k = k + 1) fdc_buf[k] = 8'hA5 ^ k[7:0];
	@(posedge clk_32); sd_lba <= 7; sd_wr <= 2'b01;
	wait (sd_ack); wait (!sd_ack);
	for (k = 0; k < 512; k = k + 1) if (fda[7*512 + k] !== (8'hA5 ^ k[7:0])) begin
		if (errors < 10) $display("write mismatch byte %0d: %02x", k, fda[7*512+k]);
		errors = errors + 1;
	end
	if (fda[8*512] !== ((8*512*13 + 8) & 8'hff)) begin $display("write spilled into LBA 8"); errors = errors + 1; end
	$display("sector write done");

	// disk swap from the Pocket menu
	@(posedge clk_74a); ds_update_id <= 1; ds_update_size <= 819200; ds_update <= 1;
	@(posedge clk_74a); ds_update <= 0;
	wait (img_mounted[0]);
	if (img_size != 819200) begin $display("remount size %0d", img_size); errors = errors + 1; end

	// ACSI hard disk: size reported, sector read at LBA 1000, write at LBA 1500
	if (hd_size0 != HD_SIZE) begin $display("hd size %0d", hd_size0); errors = errors + 1; end
	@(posedge clk_32); hd_lba <= 1000; hd_rd <= 2'b01;
	wait (hd_ack); wait (!hd_ack);
	for (k = 0; k < 512; k = k + 1) if (hd_buf[k] !== hd[1000*512 + k]) begin
		if (errors < 10) $display("hd read mismatch %0d", k); errors = errors + 1; end
	for (k = 0; k < 512; k = k + 1) hd_buf[k] = 8'h3C ^ k[7:0];
	@(posedge clk_32); hd_lba <= 1500; hd_wr <= 2'b01;
	wait (hd_ack); wait (!hd_ack);
	for (k = 0; k < 512; k = k + 1) if (hd[1500*512 + k] !== (8'h3C ^ k[7:0])) begin
		if (errors < 10) $display("hd write mismatch %0d", k); errors = errors + 1; end
	$display("hd sector read/write done");

	// warm reset: resvalid/resvector zeroed while the ST is held in reset, TOS not reloaded
	in_warm = 1; words_seen = 0;
	@(posedge clk_32); warm_req <= 1; @(posedge clk_32); warm_req <= 0;
	@(posedge clk_32);
	if (!warm_busy) begin $display("warm_busy not raised"); errors = errors + 1; end
	wait (!warm_busy);
	repeat (10) @(posedge clk_32);
	in_warm = 0;
	if (warm_seen != 4 || words_seen != 0 || !tos_done) begin
		$display("warm reset: %0d words cleared (expected 4), %0d TOS words, tos_done %b", warm_seen, words_seen, tos_done); errors = errors + 1; end
	else $display("warm reset: $426-$42D cleared");

	// cold restart (a RAM/machine change in the menu): low RAM cleared and TOS reloaded again
	clear_seen = 0; words_seen = 0;
	@(posedge clk_32); cold_req <= 1; @(posedge clk_32); cold_req <= 0;
	fork : wait_fall
		begin wait (!tos_done); disable wait_fall; end
		begin repeat (5000) @(posedge clk_32); $display("tos_done still high 5000 clocks after cold_req: ST not held in reset"); errors = errors + 1; disable wait_fall; end
	join
	wait (tos_done);
	$display("cold restart: %0d words cleared, %0d TOS words reloaded", clear_seen, words_seen);
	if (clear_seen != 2048 || words_seen != TOS_SIZE / 2 + 65536) begin $display("cold restart incomplete"); errors = errors + 1; end

	if (errors == 0) $display("PASS");
	else $display("FAIL: %0d errors", errors);
	$finish;
end

initial begin #2_000_000_000; $display("TIMEOUT"); $finish; end

endmodule
