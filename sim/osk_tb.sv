// osk testbench: drives osk_ctrl with pad presses and checks the keys it holds,
// then renders one PAL frame through st_video + osk_overlay into osk_frame.ppm.
// Run: make -C sim osk
`timescale 1ns/1ps

module osk_tb;

reg clk = 0;
always #15.58 clk = ~clk;

// ---------------- controller ----------------
reg  [15:0] pad = 0;
reg         show_loading = 0;
initial show_loading = $test$plusargs("loading");
wire        visible, mouse_toggle;
wire  [2:0] row, mods;
wire  [3:0] col;
wire  [7:0] key;

osk_ctrl ctrl (.clk(clk), .reset(1'b0), .pad(pad), .visible(visible), .cur_row(row), .cur_col(col),
	.mods(mods), .key(key), .mouse_toggle(mouse_toggle));

integer errors = 0;
task press(input integer b);  // one button, ~1 ms
	pad[b] = 1; repeat (32000) @(negedge clk); pad[b] = 0; repeat (32000) @(negedge clk);
endtask
task check(input bit cond, input [8*24-1:0] what);
	if (!cond) begin $display("FAIL %0s", what); errors = errors + 1; end
endtask

// ---------------- video ----------------
reg  [11:0] hx = 0;
reg   [9:0] vy = 0;
always @(posedge clk) begin
	hx <= (hx == 2047) ? 0 : hx + 1;
	if (hx == 2047) vy <= (vy == 312) ? 0 : vy + 1;
end
wire [23:0] st_rgb, rgb;
wire st_de, st_skip, st_hs, st_vs, de, skip, hs, vs;
// ST picture: colour bars so the overlay edges are visible
wire [3:0] bar = hx[9:6];
st_video stv (.clk(clk), .borders(1'b1), .fill(1'b0), .r(bar), .g(~bar), .b({bar[0], 3'b000}),
	.hsync_n(!(hx < 160)), .vsync_n(!(vy < 3)), .blank_n(1'b1), .monomode(1'b0),
	.video_rgb(st_rgb), .video_de(st_de), .video_skip(st_skip), .video_hs(st_hs), .video_vs(st_vs));
osk_overlay #(.FONT_FILE("../src/fpga/core/osk_font.hex")) ovl (.clk(clk), .visible(visible),
	.cur_row(row), .cur_col(col), .mods(mods), .badge(1'b1), .badge_mode(2'd2), .disk(1'b1), .disk_id(2'd0), .loading(show_loading), .load_cart(1'b0), .load_pct(12'h042),
	.in_rgb(st_rgb), .in_de(st_de), .in_skip(st_skip), .in_hs(st_hs), .in_vs(st_vs),
	.video_rgb(rgb), .video_de(de), .video_skip(skip), .video_hs(hs), .video_vs(vs));

integer f, frame = 0, n = 0;
reg capture = 0;
always @(posedge clk) begin
	if (vs) begin
		frame = frame + 1;
		if (capture && n > 0) begin $fclose(f); capture = 0; end
		if (frame == 4) begin
			f = $fopen("osk_frame.ppm", "w");
			$fwrite(f, "P3\n704 240\n255\n");
			capture = 1; n = 0;
		end
	end
	if (capture && de && !skip) begin
		$fwrite(f, "%0d %0d %0d\n", rgb[23:16], rgb[15:8], rgb[7:0]);
		n = n + 1;
	end
end

initial begin
	repeat (100) @(negedge clk);
	press(14);                                  // Select: open
	check(visible, "select opens");
	press(1); press(3); press(3);               // down, right, right -> row 1 col 2 ("W")
	check(row == 1 && col == 2, "cursor moved");
	pad[4] = 1; repeat (2000) @(negedge clk);   // hold A
	check(key == 8'h1A, "A holds W");
	pad[4] = 0; repeat (2000) @(negedge clk);
	check(key == 8'h00, "release W");
	press(1); press(1); press(2); press(2);     // row 3 col 0: SHFT
	press(4);                                   // latch shift
	check(mods == 3'b010, "shift latched");
	press(3);                                   // Z
	pad[4] = 1; repeat (2000) @(negedge clk);
	check(key == 8'h1D && mods == 3'b010, "shift+Z");
	pad[4] = 0; repeat (2000) @(negedge clk);
	check(mods == 3'b000, "shift released after key");
	press(4);                                   // types Z
	press(2); press(4);                         // back to SHFT, latch it for the picture
	press(0); press(0);                         // row 1 for the picture
	press(15);                                  // Start while visible: no mouse toggle
	check(!mouse_toggle, "start ignored while open");
	wait (frame == 5);
	$display("frame written: osk_frame.ppm");
	press(5);                                   // B closes
	check(!visible, "B closes");
	if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
	$finish;
end

endmodule
