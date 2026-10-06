// st_video testbench: synthetic GLUE syncs with the measured PAL/NTSC/mono timing
// (docs/video.md); checks that every frame has exactly the scaler mode's pixel
// count per line, line count, and slot id.
// Run: make -C sim video
`timescale 1ns/1ps

module st_video_tb;

reg clk = 0;
always #15.58 clk = ~clk;

reg  [11:0] line_len = 2048, hs_w = 160;
reg   [9:0] frame_lines = 313, vs_lines = 3;
reg         borders = 1;
reg  [11:0] hx = 0;
reg   [9:0] vy = 0;
wire hsync_n = !(hx < hs_w);
wire vsync_n = !(vy < vs_lines);
wire blank_n = 1'b1;
reg  monomode = 0;

always @(posedge clk) begin
	hx <= hx + 1;
	if (hx == line_len - 1) begin
		hx <= 0;
		vy <= (vy == frame_lines - 1) ? 0 : vy + 1;
	end
end

wire [23:0] rgb;
wire de, skip, hs, vs;
st_video dut (
	.clk(clk), .borders(borders),
	.r(hx[3:0]), .g(4'h0), .b(4'h0),
	.hsync_n(hsync_n), .vsync_n(vsync_n), .blank_n(blank_n), .monomode(monomode),
	.video_rgb(rgb), .video_de(de), .video_skip(skip), .video_hs(hs), .video_vs(vs)
);

// per-frame measurement on the APF side
integer px, lines, line_px, frames = 0, errors = 0;
integer exp_w, exp_h, exp_slot;
reg de_d = 0;
reg [2:0] slot_seen;
reg bad_line;
always @(posedge clk) begin
	de_d <= de;
	if (hs && vs) begin $display("HS and VS on the same clock"); errors = errors + 1; end
	if (vs) begin
		if (frames >= 2) begin
			if (lines != exp_h || bad_line || slot_seen != exp_slot) begin
				$display("frame %0d: %0d lines (want %0d), bad line width=%0b, slot %0d (want %0d)",
					frames, lines, exp_h, bad_line, slot_seen, exp_slot);
				errors = errors + 1;
			end
		end
		frames = frames + 1;
		lines = 0; bad_line = 0;
	end
	if (de && !de_d) line_px = 0;
	if (de && !skip) line_px = line_px + 1;
	if (!de && de_d) begin
		lines = lines + 1;
		if (line_px != exp_w) bad_line = 1;
		slot_seen = rgb[15:13];
	end
end

task run_mode(input [8*12-1:0] name, input integer ll, input integer hw, input integer fl, input integer vl,
              input integer w, input integer h, input integer slot, input bit brd);
	line_len = ll; hs_w = hw; frame_lines = fl; vs_lines = vl; borders = brd;
	exp_w = w; exp_h = h; exp_slot = slot;
	frames = 0;
	wait (frames == 5);
	$display("%0s: %0d errors so far", name, errors);
endtask

initial begin
	lines = 0; bad_line = 0; line_px = 0; slot_seen = 0;
	run_mode("PAL border",  2048, 160, 313, 3, 704, 240, 0, 1);
	run_mode("PAL full",    2048, 160, 313, 3, 640, 200, 1, 0);
	run_mode("NTSC border", 2032, 160, 263, 3, 704, 240, 2, 1);
	run_mode("NTSC full",   2032, 160, 263, 3, 640, 200, 3, 0);
	run_mode("Mono",         896,  96, 501, 1, 640, 400, 4, 1);
	if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
	$finish;
end

endmodule
