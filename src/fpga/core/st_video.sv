//
// st_video.sv - Atari ST shifter output to the APF scaler
//
// The APF video bus runs at clk_32. Colour modes are sampled every other clock
// (video_skip on the rest), so low and medium res both arrive as 640-wide lines;
// mono is sampled every clock. A fixed window is cut from each frame, anchored on
// the GLUE syncs, so DE geometry stays constant even when software plays with
// borders. Window numbers come from the gstmcu testbench; see docs/video.md.
//

`default_nettype none

module st_video (
	input  wire        clk,         // clk_32, also the APF video clock
	input  wire        borders,     // 1: show part of the border area

	input  wire  [3:0] r,
	input  wire  [3:0] g,
	input  wire  [3:0] b,
	input  wire        hsync_n,
	input  wire        vsync_n,
	input  wire        blank_n,
	input  wire        monomode,

	output reg  [23:0] video_rgb,
	output reg         video_de,
	output reg         video_skip,
	output reg         video_hs,
	output reg         video_vs
);

// Scaler slots, in video.json order
localparam [2:0] SLOT_PAL_BORDER  = 3'd0;
localparam [2:0] SLOT_PAL_FULL    = 3'd1;
localparam [2:0] SLOT_NTSC_BORDER = 3'd2;
localparam [2:0] SLOT_NTSC_FULL   = 3'd3;
localparam [2:0] SLOT_MONO        = 3'd4;

localparam MODE_PAL = 2'd0, MODE_NTSC = 2'd1, MODE_MONO = 2'd2;

reg [11:0] x;
reg  [9:0] y;
reg  [9:0] lines;           // lines in the frame being drawn
reg  [1:0] mode;
reg        hsync_n_d, vsync_n_d;

wire hs_fall = hsync_n_d & ~hsync_n;
wire vs_fall = vsync_n_d & ~vsync_n;

// window: x in clk_32 cycles from the hsync fall, y in lines from the vsync fall
reg [11:0] x0, x1;
reg  [9:0] y0, y1;
reg  [2:0] slot;

always @(*) begin
	case (mode)
		MODE_MONO: begin
			// the 640 pixels exactly: the 896-clock line leaves no room for a margin after them
			x0 = 12'd246;  x1 = 12'd886;  y0 = 10'd37; y1 = 10'd437; slot = SLOT_MONO;
		end
		MODE_NTSC: begin
			if (borders) begin x0 = 12'd448; x1 = 12'd1856; y0 = 10'd17; y1 = 10'd257; slot = SLOT_NTSC_BORDER; end
			else         begin x0 = 12'd512; x1 = 12'd1792; y0 = 10'd37; y1 = 10'd237; slot = SLOT_NTSC_FULL; end
		end
		default: begin
			if (borders) begin x0 = 12'd464; x1 = 12'd1872; y0 = 10'd46; y1 = 10'd286; slot = SLOT_PAL_BORDER; end
			else         begin x0 = 12'd528; x1 = 12'd1808; y0 = 10'd66; y1 = 10'd266; slot = SLOT_PAL_FULL; end
		end
	endcase
end

wire in_window = (x >= x0) && (x < x1) && (y >= y0) && (y < y1);
wire [11:0] wx = x - x0;
reg  hs_late;

always @(posedge clk) begin
	hsync_n_d <= hsync_n;
	vsync_n_d <= vsync_n;

	x <= x + 12'd1;
	if (hs_fall) begin
		x <= 12'd1;
		y <= y + 10'd1;
		lines <= lines + 10'd1;
	end

	// the window for a frame is chosen from the previous frame's line count
	if (vs_fall) begin
		y <= 10'd0;
		lines <= 10'd0;
		mode <= (lines > 10'd400) ? MODE_MONO : (lines > 10'd290) ? MODE_PAL : MODE_NTSC;
	end

	// HS and VS must not share a clock
	video_vs <= vs_fall;
	video_hs <= 1'b0;
	hs_late <= 1'b0;
	if (x == 12'd3) begin
		if (vs_fall) hs_late <= 1'b1;
		else         video_hs <= 1'b1;
	end
	if (hs_late) video_hs <= 1'b1;

	video_de   <= in_window;
	video_skip <= in_window && (mode != MODE_MONO) && wx[0];

	if (in_window)
		video_rgb <= (blank_n | monomode) ? {r, r, g, g, b, b} : 24'h000000;
	else if (video_de)
		video_rgb <= {8'h00, slot, 13'h0000};   // end of line: scaler slot select
	else
		video_rgb <= 24'h000000;
end

endmodule

`default_nettype wire
