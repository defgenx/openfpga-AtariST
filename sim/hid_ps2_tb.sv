// hid_ps2 testbench: drives MiSTery's own PS/2 decoder (ikbd/ps2.sv) and checks
// the IKBD key matrix and mouse quadrature it produces.
// Run: make -C sim hid
`timescale 1ns/1ps

module hid_ps2_tb;

reg clk_32 = 0, clk_2 = 0;
always #15.58 clk_32 = ~clk_32;
always #249.3 clk_2 = ~clk_2;

reg         reset = 1;
reg         kbd_present = 1;
reg  [47:0] kbd_codes = 0;
reg   [7:0] kbd_mods = 0;
reg  [39:0] pad_keys = 0;
reg         mouse_event = 0;
reg  signed [15:0] mouse_dx = 0, mouse_dy = 0;
reg   [2:0] mouse_buttons = 0;
wire kclk, kdat, mclk, mdat;

hid_ps2 dut (
	.clk(clk_32), .reset(reset),
	.kbd_present(kbd_present), .kbd_codes(kbd_codes), .kbd_mods(kbd_mods),
	.pad_keys(pad_keys),
	.mouse_event(mouse_event), .mouse_dx(mouse_dx), .mouse_dy(mouse_dy), .mouse_buttons(mouse_buttons),
	.kbd_clk(kclk), .kbd_data(kdat), .mouse_clk(mclk), .mouse_data(mdat)
);

wire [7:0] matrix[14:0];
wire [5:0] mouse_atari;
wire       joy_toggle;
ps2 ikbd_ps2 (
	.clk(clk_2), .reset(reset),
	.kbd_clk(kclk), .kbd_data(kdat), .matrix(matrix),
	.mouse_clk(mclk), .mouse_data(mdat), .mouse_atari(mouse_atari),
	.joy_port_toggle(joy_toggle)
);

integer errors = 0;
task expect_key(input integer row, input integer col, input bit pressed, input [8*16-1:0] name);
	if (matrix[row][col] !== !pressed) begin
		$display("FAIL %0s: matrix[%0d][%0d] = %b", name, row, col, matrix[row][col]);
		errors = errors + 1;
	end
endtask

task settle; #4_000_000; endtask   // 4 ms: a few PS/2 bytes

// count quadrature steps on the IKBD mouse lines
integer xsteps = 0, ysteps = 0;
reg [1:0] qx_d = 0, qy_d = 0;
always @(posedge clk_2) begin
	qx_d <= mouse_atari[1:0];
	qy_d <= mouse_atari[3:2];
	// mouse_atari counters are 2-bit gray codes: +1 = 00->10->11->01 for "positive"
	if (mouse_atari[1:0] != qx_d) xsteps = xsteps + ((mouse_atari[1:0] == {qx_d[0], ~qx_d[1]}) ? -1 : 1);
	if (mouse_atari[3:2] != qy_d) ysteps = ysteps + ((mouse_atari[3:2] == {qy_d[0], ~qy_d[1]}) ? -1 : 1);
end

initial begin
	#2000 reset = 0;
	#10000;

	// 'a' down
	kbd_codes = {40'd0, 8'h04}; settle;
	expect_key(4, 5, 1, "a down");
	// add up-arrow (E0 prefix) in another slot and left shift
	kbd_codes = {32'd0, 8'h52, 8'h04}; kbd_mods = 8'h02; settle; settle;
	expect_key(4, 5, 1, "a held");
	expect_key(12, 1, 1, "up down");
	expect_key(1, 5, 1, "lshift down");
	// release 'a' only; codes can move between slots
	kbd_codes = {40'd0, 8'h52}; settle;
	expect_key(4, 5, 0, "a up");
	expect_key(12, 1, 1, "up held");
	// release everything
	kbd_codes = 0; kbd_mods = 0; settle; settle;
	expect_key(12, 1, 0, "up up");
	expect_key(1, 5, 0, "lshift up");
	// pad-injected space
	pad_keys = 40'h2C; settle;
	expect_key(9, 7, 1, "pad space");
	pad_keys = 0; settle;
	expect_key(9, 7, 0, "pad space up");
	// on-screen keyboard: 'q' with latched shift, in the upper pad slots
	pad_keys = {8'h14, 8'hE1, 24'd0}; settle; settle;
	expect_key(4, 4, 1, "osk q");
	expect_key(1, 5, 1, "osk shift");
	pad_keys = 0; settle; settle;
	expect_key(4, 4, 0, "osk q up");
	expect_key(1, 5, 0, "osk shift up");
	// keyboard unplugged while a key is down releases it
	kbd_codes = {40'd0, 8'h1E}; settle;
	expect_key(4, 2, 1, "1 down");
	kbd_present = 0; settle;
	expect_key(4, 2, 0, "1 released on unplug");
	kbd_present = 1;

	// mouse: +40 right, +25 down, then left button
	@(posedge clk_32); mouse_dx = 40; mouse_dy = 25; mouse_event = 1;
	@(posedge clk_32); mouse_event = 0;
	#60_000_000;
	if (xsteps != 40 || ysteps != 25) begin
		$display("FAIL mouse steps x=%0d y=%0d (want 40 25)", xsteps, ysteps); errors = errors + 1;
	end
	@(posedge clk_32); mouse_dx = -12; mouse_dy = -7; mouse_event = 1;
	@(posedge clk_32); mouse_event = 0;
	#30_000_000;
	if (xsteps != 28 || ysteps != 18) begin
		$display("FAIL mouse steps after back x=%0d y=%0d (want 28 18)", xsteps, ysteps); errors = errors + 1;
	end
	mouse_buttons = 3'b001; #8_000_000;
	if (mouse_atari[5:4] != 2'b01) begin $display("FAIL left button %b", mouse_atari[5:4]); errors = errors + 1; end
	mouse_buttons = 3'b000; #8_000_000;
	if (mouse_atari[5:4] != 2'b00) begin $display("FAIL button release %b", mouse_atari[5:4]); errors = errors + 1; end

	if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
	$finish;
end

endmodule
