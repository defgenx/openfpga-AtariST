//
// hid_ps2.sv - Dock USB keyboard/mouse (and pad emulation) to PS/2 device streams
//
// MiSTery's IKBD (ikbd/ps2.sv) decodes PS/2 set 2 keyboard bytes and 4-byte
// IntelliMouse packets. This module plays the PS/2 *device* side so the IKBD
// stays untouched. Key mapping follows ikbd/ps2.sv; see docs/input.md.
//

`default_nettype none

module hid_ps2 (
	input  wire        clk,            // clk_32
	input  wire        reset,

	// Dock keyboard: 6 HID usages + modifier byte, valid when kbd_present
	input  wire        kbd_present,
	input  wire [47:0] kbd_codes,
	input  wire  [7:0] kbd_mods,
	// keys injected by the pad mapping and the on-screen keyboard (11 HID usages, 0 = none)
	input  wire [87:0] pad_keys,

	// relative mouse motion, already summed by the caller; pulses on new report
	input  wire        mouse_event,
	input  wire signed [15:0] mouse_dx,   // + = right
	input  wire signed [15:0] mouse_dy,   // + = down (HID convention)
	input  wire  [2:0] mouse_buttons,     // {middle, right, left}

	output wire        kbd_clk,
	output wire        kbd_data,
	output wire        mouse_clk,
	output wire        mouse_data
);

/* ------------------------------------------------------------------------ */
/* HID usage -> PS/2 set 2 (bit 8 = needs E0 prefix, 0 = unmapped)          */
/* ------------------------------------------------------------------------ */

function [8:0] hid2ps2(input [7:0] u);
	case (u)
		8'h04: hid2ps2 = 9'h01C; 8'h05: hid2ps2 = 9'h032; 8'h06: hid2ps2 = 9'h021; 8'h07: hid2ps2 = 9'h023;
		8'h08: hid2ps2 = 9'h024; 8'h09: hid2ps2 = 9'h02B; 8'h0A: hid2ps2 = 9'h034; 8'h0B: hid2ps2 = 9'h033;
		8'h0C: hid2ps2 = 9'h043; 8'h0D: hid2ps2 = 9'h03B; 8'h0E: hid2ps2 = 9'h042; 8'h0F: hid2ps2 = 9'h04B;
		8'h10: hid2ps2 = 9'h03A; 8'h11: hid2ps2 = 9'h031; 8'h12: hid2ps2 = 9'h044; 8'h13: hid2ps2 = 9'h04D;
		8'h14: hid2ps2 = 9'h015; 8'h15: hid2ps2 = 9'h02D; 8'h16: hid2ps2 = 9'h01B; 8'h17: hid2ps2 = 9'h02C;
		8'h18: hid2ps2 = 9'h03C; 8'h19: hid2ps2 = 9'h02A; 8'h1A: hid2ps2 = 9'h01D; 8'h1B: hid2ps2 = 9'h022;
		8'h1C: hid2ps2 = 9'h035; 8'h1D: hid2ps2 = 9'h01A;
		8'h1E: hid2ps2 = 9'h016; 8'h1F: hid2ps2 = 9'h01E; 8'h20: hid2ps2 = 9'h026; 8'h21: hid2ps2 = 9'h025;
		8'h22: hid2ps2 = 9'h02E; 8'h23: hid2ps2 = 9'h036; 8'h24: hid2ps2 = 9'h03D; 8'h25: hid2ps2 = 9'h03E;
		8'h26: hid2ps2 = 9'h046; 8'h27: hid2ps2 = 9'h045;
		8'h28: hid2ps2 = 9'h05A; // return
		8'h29: hid2ps2 = 9'h076; // esc
		8'h2A: hid2ps2 = 9'h066; // backspace
		8'h2B: hid2ps2 = 9'h00D; // tab
		8'h2C: hid2ps2 = 9'h029; // space
		8'h2D: hid2ps2 = 9'h04E; 8'h2E: hid2ps2 = 9'h055; 8'h2F: hid2ps2 = 9'h054; 8'h30: hid2ps2 = 9'h05B;
		8'h31: hid2ps2 = 9'h05D; 8'h32: hid2ps2 = 9'h05D; 8'h33: hid2ps2 = 9'h04C; 8'h34: hid2ps2 = 9'h052;
		8'h35: hid2ps2 = 9'h00E; 8'h36: hid2ps2 = 9'h041; 8'h37: hid2ps2 = 9'h049; 8'h38: hid2ps2 = 9'h04A;
		8'h39: hid2ps2 = 9'h058; // caps lock
		8'h3A: hid2ps2 = 9'h005; 8'h3B: hid2ps2 = 9'h006; 8'h3C: hid2ps2 = 9'h004; 8'h3D: hid2ps2 = 9'h00C;
		8'h3E: hid2ps2 = 9'h003; 8'h3F: hid2ps2 = 9'h00B; 8'h40: hid2ps2 = 9'h083; 8'h41: hid2ps2 = 9'h00A;
		8'h42: hid2ps2 = 9'h001; 8'h43: hid2ps2 = 9'h009; 8'h44: hid2ps2 = 9'h078; // F11 = joystick port toggle
		8'h46: hid2ps2 = 9'h17C; // print screen -> KP (
		8'h49: hid2ps2 = 9'h170; // insert
		8'h4A: hid2ps2 = 9'h16C; // home
		8'h4B: hid2ps2 = 9'h17D; // page up -> HELP
		8'h4C: hid2ps2 = 9'h171; // delete
		8'h4D: hid2ps2 = 9'h169; // end -> KP )
		8'h4E: hid2ps2 = 9'h17A; // page down -> UNDO
		8'h4F: hid2ps2 = 9'h174; 8'h50: hid2ps2 = 9'h16B; 8'h51: hid2ps2 = 9'h172; 8'h52: hid2ps2 = 9'h175;
		8'h54: hid2ps2 = 9'h14A; 8'h55: hid2ps2 = 9'h07C; 8'h56: hid2ps2 = 9'h07B; 8'h57: hid2ps2 = 9'h079;
		8'h58: hid2ps2 = 9'h15A; // keypad enter
		8'h59: hid2ps2 = 9'h069; 8'h5A: hid2ps2 = 9'h072; 8'h5B: hid2ps2 = 9'h07A; 8'h5C: hid2ps2 = 9'h06B;
		8'h5D: hid2ps2 = 9'h073; 8'h5E: hid2ps2 = 9'h074; 8'h5F: hid2ps2 = 9'h06C; 8'h60: hid2ps2 = 9'h075;
		8'h61: hid2ps2 = 9'h07D; 8'h62: hid2ps2 = 9'h070; 8'h63: hid2ps2 = 9'h071;
		8'h64: hid2ps2 = 9'h061; // non-US backslash -> ISO key
		// modifier bits are presented as usages E0-E7
		8'hE0: hid2ps2 = 9'h014; 8'hE1: hid2ps2 = 9'h012; 8'hE2: hid2ps2 = 9'h011;
		8'hE4: hid2ps2 = 9'h114; 8'hE5: hid2ps2 = 9'h059; 8'hE6: hid2ps2 = 9'h011;
		default: hid2ps2 = 9'h000;
	endcase
endfunction

/* ------------------------------------------------------------------------ */
/* Keyboard: diff the current key set against the set already reported      */
/* ------------------------------------------------------------------------ */

localparam N = 25; // 6 dock keys + 8 modifiers + 11 pad/OSK keys

wire [7:0] cur[N];
genvar gi;
generate
	for (gi = 0; gi < 6; gi = gi + 1) begin : g_codes
		assign cur[gi] = kbd_present ? kbd_codes[gi*8 +: 8] : 8'h00;
	end
	for (gi = 0; gi < 8; gi = gi + 1) begin : g_mods
		assign cur[6+gi] = (kbd_present && kbd_mods[gi]) ? (8'hE0 + 8'(gi)) : 8'h00;
	end
	for (gi = 0; gi < 11; gi = gi + 1) begin : g_pad
		assign cur[14+gi] = pad_keys[gi*8 +: 8];
	end
endgenerate

reg [7:0] sent[N];          // keys whose make code has been sent

// first released key / first new key
reg       rel_found, new_found;
reg [4:0] rel_idx, new_idx;
always @(*) begin
	integer i, j;
	reg hit;
	rel_found = 1'b0; rel_idx = 5'd0;
	new_found = 1'b0; new_idx = 5'd0;
	for (i = N-1; i >= 0; i = i - 1) begin
		hit = 1'b0;
		for (j = 0; j < N; j = j + 1) if (cur[j] == sent[i]) hit = 1'b1;
		if (sent[i] != 8'h00 && !hit) begin rel_found = 1'b1; rel_idx = i[4:0]; end
	end
	for (i = N-1; i >= 0; i = i - 1) begin
		hit = 1'b0;
		for (j = 0; j < N; j = j + 1) if (sent[j] == cur[i]) hit = 1'b1;
		if (cur[i] != 8'h00 && hid2ps2(cur[i]) != 9'h000 && !hit) begin new_found = 1'b1; new_idx = i[4:0]; end
	end
end

// byte sequence for one key event: [E0] [F0] code
reg  [7:0] kq[3];
reg  [1:0] kq_len, kq_pos;
reg        k_busy;
wire       k_tx_ready;
reg        k_tx_start;
reg  [7:0] k_tx_byte;

always @(posedge clk) begin
	integer i;
	reg [8:0] code;
	k_tx_start <= 1'b0;

	if (reset) begin
		for (i = 0; i < N; i = i + 1) sent[i] <= 8'h00;
		k_busy <= 1'b0;
	end else if (!k_busy) begin
		if (rel_found) begin
			code = hid2ps2(sent[rel_idx]);
			sent[rel_idx] <= 8'h00;
			if (code[8]) begin kq[0] <= 8'hE0; kq[1] <= 8'hF0; kq[2] <= code[7:0]; kq_len <= 2'd3; end
			else         begin kq[0] <= 8'hF0; kq[1] <= code[7:0]; kq_len <= 2'd2; end
			kq_pos <= 2'd0;
			k_busy <= 1'b1;
		end else if (new_found) begin
			code = hid2ps2(cur[new_idx]);
			sent[new_idx] <= cur[new_idx];
			if (code[8]) begin kq[0] <= 8'hE0; kq[1] <= code[7:0]; kq_len <= 2'd2; end
			else         begin kq[0] <= code[7:0]; kq_len <= 2'd1; end
			kq_pos <= 2'd0;
			k_busy <= 1'b1;
		end
	end else if (k_tx_ready && !k_tx_start) begin
		if (kq_pos == kq_len) k_busy <= 1'b0;
		else begin
			k_tx_byte <= kq[kq_pos];
			k_tx_start <= 1'b1;
			kq_pos <= kq_pos + 2'd1;
		end
	end
end

ps2_device_tx kbd_tx (
	.clk(clk), .reset(reset),
	.start(k_tx_start), .data(k_tx_byte), .ready(k_tx_ready),
	.ps2_clk(kbd_clk), .ps2_data(kbd_data)
);

/* ------------------------------------------------------------------------ */
/* Mouse: accumulate motion, send small packets the IKBD can drain          */
/* ------------------------------------------------------------------------ */

// ps2.sv replaces (not adds) its pending motion with each packet and drains it
// at ~2000 steps/s, so each packet must stay within what one packet time drains.
localparam signed [15:0] STEP_MAX = 16'sd6;
localparam signed [15:0] ACC_MAX  = 16'sd1024;

reg signed [15:0] acc_x, acc_y;
reg  [2:0] btn_sent;
reg  [7:0] mq[4];
reg  [2:0] mq_pos;
reg        m_busy;
wire       m_tx_ready;
reg        m_tx_start;
reg  [7:0] m_tx_byte;

function signed [15:0] clamp(input signed [15:0] v, input signed [15:0] lim);
	clamp = (v > lim) ? lim : (v < -lim) ? -lim : v;
endfunction

always @(posedge clk) begin
	reg signed [15:0] sx, sy, nx, ny;
	m_tx_start <= 1'b0;

	if (reset) begin
		acc_x <= 0; acc_y <= 0;
		btn_sent <= 3'b000;
		m_busy <= 1'b0;
	end else begin
		nx = acc_x; ny = acc_y;
		if (mouse_event) begin
			nx = clamp(acc_x + mouse_dx, ACC_MAX);
			ny = clamp(acc_y + mouse_dy, ACC_MAX);
		end

		if (!m_busy) begin
			if (nx != 0 || ny != 0 || mouse_buttons != btn_sent) begin
				sx = clamp(nx, STEP_MAX);
				sy = -clamp(ny, STEP_MAX);       // PS/2 Y grows upwards
				nx = nx - sx;
				ny = ny + sy;
				mq[0] <= {2'b00, sy[15], sx[15], 1'b1, mouse_buttons[2], mouse_buttons[1], mouse_buttons[0]};
				mq[1] <= sx[7:0];
				mq[2] <= sy[7:0];
				mq[3] <= 8'h00;                  // wheel
				btn_sent <= mouse_buttons;
				mq_pos <= 3'd0;
				m_busy <= 1'b1;
			end
		end else if (m_tx_ready && !m_tx_start) begin
			if (mq_pos == 3'd4) m_busy <= 1'b0;
			else begin
				m_tx_byte <= mq[mq_pos[1:0]];
				m_tx_start <= 1'b1;
				mq_pos <= mq_pos + 3'd1;
			end
		end

		acc_x <= nx;
		acc_y <= ny;
	end
end

ps2_device_tx mouse_tx (
	.clk(clk), .reset(reset),
	.start(m_tx_start), .data(m_tx_byte), .ready(m_tx_ready),
	.ps2_clk(mouse_clk), .ps2_data(mouse_data)
);

endmodule


//
// PS/2 device-to-host byte transmitter: start, 8 data bits LSB first, odd parity, stop.
// The host samples data on the falling clock edge.
//
module ps2_device_tx #(
	parameter HALF_BIT = 1024,   // clk cycles per half PS/2 clock (~15.6 kHz at 32 MHz)
	parameter GAP      = 8192    // idle clocks between bytes
) (
	input  wire       clk,
	input  wire       reset,
	input  wire       start,
	input  wire [7:0] data,
	output wire       ready,
	output reg        ps2_clk,
	output reg        ps2_data
);

reg [10:0] frame;
reg  [3:0] bit_cnt;
reg [13:0] timer;
reg        phase;      // 0: clock high, data set; 1: clock low
reg        active;
reg        gap;

assign ready = !active && !gap && !start;

always @(posedge clk) begin
	if (reset) begin
		ps2_clk <= 1'b1;
		ps2_data <= 1'b1;
		active <= 1'b0;
		gap <= 1'b0;
	end else if (start && !active) begin
		frame <= {1'b1, ~^data, data, 1'b0};  // stop, parity, data, start
		bit_cnt <= 4'd0;
		timer <= 14'd0;
		phase <= 1'b0;
		active <= 1'b1;
	end else if (active) begin
		timer <= timer + 14'd1;
		if (timer == HALF_BIT - 1) begin
			timer <= 14'd0;
			if (!phase) begin
				if (bit_cnt == 4'd11) begin
					active <= 1'b0;
					gap <= 1'b1;
					ps2_data <= 1'b1;
				end else begin
					ps2_data <= frame[bit_cnt];
					phase <= 1'b1;
				end
			end else begin
				ps2_clk <= ~ps2_clk;
				if (!ps2_clk) begin
					phase <= 1'b0;
					bit_cnt <= bit_cnt + 4'd1;
				end
			end
		end
	end else if (gap) begin
		timer <= timer + 14'd1;
		if (timer == GAP - 1) begin
			gap <= 1'b0;
			timer <= 14'd0;
		end
	end
end

endmodule

`default_nettype wire
