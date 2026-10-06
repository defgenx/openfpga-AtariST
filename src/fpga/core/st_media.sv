//
// st_media.sv - TOS loading and floppy sector access over APF target commands
//
// Every data slot is "deferload": nothing is pushed by APF at boot. This module
// pulls the TOS ROM in 16 KB chunks and serves the FDC's 512-byte sector requests
// with Dataslot Read/Write target commands, so all transfers are flow-controlled
// by the core. See docs/architecture.md for the full sequence.
//
// Bridge map:
//   0x1000_0000-0x1000_3FFF  read buffer  (APF writes into it)
//   0x1000_8000-0x1000_81FF  write buffer (APF reads from it)
//

`default_nettype none

module st_media (
	input  wire        clk_74a,
	input  wire        clk_32,

	// APF bridge (clk_74a)
	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,
	output reg  [31:0] bridge_rd_data,

	// target commands (clk_74a)
	output reg         target_dataslot_read,
	output reg         target_dataslot_write,
	output reg  [15:0] target_dataslot_id,
	output reg  [31:0] target_dataslot_slotoffset,
	output reg  [31:0] target_dataslot_bridgeaddr,
	output reg  [31:0] target_dataslot_length,
	input  wire        target_dataslot_done,
	input  wire  [2:0] target_dataslot_err,

	// host notifications (clk_74a)
	input  wire        dataslot_update,
	input  wire [15:0] dataslot_update_id,
	input  wire [31:0] dataslot_update_size,
	input  wire        dataslot_allcomplete,
	output reg   [9:0] datatable_addr,
	input  wire [31:0] datatable_q,

	// ST side (clk_32)
	input  wire        cold_req,       // pulse: clear low RAM, reload TOS, restart
	input  wire        warm_req,       // pulse: clear the reset-proof vector before a warm reset
	output wire        warm_busy,      // keep the ST in reset until that is done
	output reg         tos_done,
	output wire        load_cart,      // loading screen: cartridge rather than TOS
	output reg  [11:0] load_pct = 12'h000, // loading screen: progress, 3 BCD digits (000-100)

	output reg         data_download,
	output reg  [23:1] data_addr,
	output reg  [15:0] data_in_reg,
	output reg         data_in_strobe,     // toggles once per word

	output reg   [1:0] img_mounted,
	output reg  [31:0] img_size,
	input  wire [31:0] sd_lba,
	input  wire  [1:0] sd_rd,
	input  wire  [1:0] sd_wr,
	output reg         sd_ack,
	output reg   [8:0] sd_buff_addr,
	output reg   [7:0] sd_dout,
	output reg         sd_dout_strobe,
	input  wire  [7:0] sd_din,

	// ACSI hard disks (clk_32): same sector handshake, separate ack and buffer
	input  wire  [1:0] hd_rd,
	input  wire  [1:0] hd_wr,
	input  wire [31:0] hd_lba,
	output reg         hd_ack,
	input  wire  [7:0] hd_din,
	output reg  [31:0] hd_size0,       // bytes, 0 = no image (clk_74a, quasi-static)
	output reg  [31:0] hd_size1
);

// Slot ids, kept in sync with data.json
localparam [15:0] SLOT_TOS   = 16'd0;
localparam [15:0] SLOT_FDD_A = 16'd1;
localparam [15:0] SLOT_FDD_B = 16'd2;
localparam [15:0] SLOT_HDD_0 = 16'd3;
localparam [15:0] SLOT_HDD_1 = 16'd4;
localparam [15:0] SLOT_CART  = 16'd5;

localparam [31:0] RBUF_ADDR = 32'h1000_0000;
// clocks between ROM words: MiSTery takes one per 16-clock bus slot; 2x margin
localparam [5:0] STROBE_GAP = 6'd31;
localparam [31:0] WBUF_ADDR = 32'h1000_8000;

/* ------------------------------------------------------------------------ */
/* Buffers: one byte lane per RAM so the 32-bit bridge side and the 8-bit   */
/* ST side infer plain dual-clock M10K blocks.                              */
/* ------------------------------------------------------------------------ */

reg [7:0] rbuf0[4096], rbuf1[4096], rbuf2[4096], rbuf3[4096];   // 16 KB
wire      rbuf_we = bridge_wr && bridge_addr[31:14] == RBUF_ADDR[31:14];

always @(posedge clk_74a) if (rbuf_we) begin
	rbuf0[bridge_addr[13:2]] <= bridge_wr_data[31:24];
	rbuf1[bridge_addr[13:2]] <= bridge_wr_data[23:16];
	rbuf2[bridge_addr[13:2]] <= bridge_wr_data[15:8];
	rbuf3[bridge_addr[13:2]] <= bridge_wr_data[7:0];
end

reg [13:0] rbuf_raddr;
reg  [7:0] rq0, rq1, rq2, rq3;
reg  [1:0] rbuf_lane;
always @(posedge clk_32) begin
	rq0 <= rbuf0[rbuf_raddr[13:2]];
	rq1 <= rbuf1[rbuf_raddr[13:2]];
	rq2 <= rbuf2[rbuf_raddr[13:2]];
	rq3 <= rbuf3[rbuf_raddr[13:2]];
	rbuf_lane <= rbuf_raddr[1:0];
end
wire [7:0] rbuf_q = rbuf_lane == 2'd0 ? rq0 : rbuf_lane == 2'd1 ? rq1 : rbuf_lane == 2'd2 ? rq2 : rq3;

reg [7:0] wbuf0[128], wbuf1[128], wbuf2[128], wbuf3[128];
reg       wbuf_we;
reg [8:0] wbuf_waddr;
reg [7:0] wbuf_wdata;
always @(posedge clk_32) if (wbuf_we) begin
	case (wbuf_waddr[1:0])
		2'd0: wbuf0[wbuf_waddr[8:2]] <= wbuf_wdata;
		2'd1: wbuf1[wbuf_waddr[8:2]] <= wbuf_wdata;
		2'd2: wbuf2[wbuf_waddr[8:2]] <= wbuf_wdata;
		2'd3: wbuf3[wbuf_waddr[8:2]] <= wbuf_wdata;
	endcase
end

always @(posedge clk_74a)
	bridge_rd_data <= {wbuf0[bridge_addr[8:2]], wbuf1[bridge_addr[8:2]], wbuf2[bridge_addr[8:2]], wbuf3[bridge_addr[8:2]]};

/* ------------------------------------------------------------------------ */
/* clk_74a: slot sizes and the target command engine                        */
/* ------------------------------------------------------------------------ */

reg        boot_ready_74;       // datatable has been scanned
reg [31:0] size_74[2];
reg  [1:0] mount_t_74;          // toggles when a new image is available
reg        tos_t_74;            // toggles when a new TOS (or cartridge) is picked from the menu
reg [31:0] cart_size_74;        // bytes, 0 = no cartridge

// Datatable layout: two words per slot, {id} then {size}.
// mf_datatable registers address and output: q is valid 2 clocks after the address.
reg  [5:0] dt_idx;
reg  [2:0] dt_phase;
reg        dt_scanning;
reg [15:0] dt_id;

always @(posedge clk_74a) begin
	if (dataslot_allcomplete && !boot_ready_74 && !dt_scanning) begin
		dt_scanning <= 1'b1;
		dt_idx <= 6'd0;
		dt_phase <= 3'd0;
	end

	if (dt_scanning) begin
		dt_phase <= dt_phase + 3'd1;
		case (dt_phase)
			3'd0: datatable_addr <= {3'd0, dt_idx, 1'b0};
			3'd3: begin
				dt_id <= datatable_q[15:0];
				datatable_addr <= {3'd0, dt_idx, 1'b1};
			end
			3'd7: begin
				if (dt_id == SLOT_FDD_A && datatable_q != 0) begin size_74[0] <= datatable_q; mount_t_74[0] <= ~mount_t_74[0]; end
				if (dt_id == SLOT_FDD_B && datatable_q != 0) begin size_74[1] <= datatable_q; mount_t_74[1] <= ~mount_t_74[1]; end
				if (dt_id == SLOT_HDD_0) hd_size0 <= datatable_q;
				if (dt_id == SLOT_HDD_1) hd_size1 <= datatable_q;
				if (dt_id == SLOT_CART)  cart_size_74 <= datatable_q;
				dt_idx <= dt_idx + 6'd1;
				if (dt_idx == 6'd31) begin
					dt_scanning <= 1'b0;
					boot_ready_74 <= 1'b1;
				end
			end
			default: ;
		endcase
	end

	// a disk or TOS picked from the Pocket menu while running
	if (dataslot_update) begin
		if (dataslot_update_id == SLOT_TOS && boot_ready_74) tos_t_74 <= ~tos_t_74;
		if (dataslot_update_id == SLOT_FDD_A) begin size_74[0] <= dataslot_update_size; mount_t_74[0] <= ~mount_t_74[0]; end
		if (dataslot_update_id == SLOT_FDD_B) begin size_74[1] <= dataslot_update_size; mount_t_74[1] <= ~mount_t_74[1]; end
		if (dataslot_update_id == SLOT_HDD_0) hd_size0 <= dataslot_update_size;
		if (dataslot_update_id == SLOT_HDD_1) hd_size1 <= dataslot_update_size;
		if (dataslot_update_id == SLOT_CART)  begin cart_size_74 <= dataslot_update_size; if (boot_ready_74) tos_t_74 <= ~tos_t_74; end
	end
end

// request from clk_32: parameters are held stable while req_t != ack_t
reg        req_t;
reg        req_write;
reg [15:0] req_slot;
reg [31:0] req_offset;
reg [31:0] req_length;
reg [31:0] req_bridgeaddr;
reg        ack_t_74;

reg  [2:0] req_t_s;
always @(posedge clk_74a) req_t_s <= {req_t_s[1:0], req_t};

// A command APF answers with an error code is sent again after ~1 ms, up to 7 times;
// acknowledging it would hand the FDC whatever the read buffer held before.
localparam E_IDLE = 3'd0, E_START = 3'd1, E_WAIT_LOW = 3'd2, E_WAIT_DONE = 3'd3, E_BACKOFF = 3'd4;
reg  [2:0] estate;
reg  [2:0] retries;
reg [16:0] backoff;

always @(posedge clk_74a) begin
	target_dataslot_read  <= 1'b0;
	target_dataslot_write <= 1'b0;

	case (estate)
		E_IDLE: if (req_t_s[2] != ack_t_74) begin
			target_dataslot_id         <= req_slot;
			target_dataslot_slotoffset <= req_offset;
			target_dataslot_length     <= req_length;
			target_dataslot_bridgeaddr <= req_bridgeaddr;
			retries <= 3'd0;
			estate <= E_START;
		end
		E_START: begin
			if (req_write) target_dataslot_write <= 1'b1;
			else           target_dataslot_read  <= 1'b1;
			estate <= E_WAIT_LOW;
		end
		// done stays high from the previous command until the bridge starts this one
		E_WAIT_LOW:  if (!target_dataslot_done) estate <= E_WAIT_DONE;
		E_WAIT_DONE: if (target_dataslot_done) begin
			if (target_dataslot_err != 3'd0 && retries != 3'd7) begin
				retries <= retries + 3'd1;
				backoff <= 17'd0;
				estate <= E_BACKOFF;
			end else begin
				ack_t_74 <= req_t_s[2];
				estate <= E_IDLE;
			end
		end
		E_BACKOFF: begin
			backoff <= backoff + 17'd1;
			if (backoff == 17'h1FFFF) estate <= E_START;
		end
		default: estate <= E_IDLE;
	endcase
end

/* ------------------------------------------------------------------------ */
/* clk_32: TOS loader and FDC sector server                                 */
/* ------------------------------------------------------------------------ */

reg [2:0] ack_t_s, boot_s;
reg [2:0] mount_s0, mount_s1, tos_s;
reg       tos_seen, tos_pending;
reg       warm_pending;
always @(posedge clk_32) begin
	ack_t_s  <= {ack_t_s[1:0], ack_t_74};
	boot_s   <= {boot_s[1:0], boot_ready_74};
	mount_s0 <= {mount_s0[1:0], mount_t_74[0]};
	mount_s1 <= {mount_s1[1:0], mount_t_74[1]};
	tos_s    <= {tos_s[1:0], tos_t_74};
end
wire req_busy = req_t != ack_t_s[2];

localparam [4:0]
	S_BOOT       = 5'd0,
	S_TOS_REQ    = 5'd1,
	S_TOS_WAIT   = 5'd2,
	S_TOS_HDR    = 5'd3,
	S_TOS_HI     = 5'd4,
	S_TOS_LO     = 5'd5,
	S_TOS_PACE   = 5'd6,
	S_IDLE       = 5'd7,
	S_MOUNT      = 5'd8,
	S_FD_RD_WAIT = 5'd9,
	S_FD_RD_DATA = 5'd10,
	S_FD_WR_DATA = 5'd11,
	S_FD_WR_WAIT = 5'd12,
	S_FD_END     = 5'd13,
	S_CLEAR      = 5'd14,
	S_WARM       = 5'd15;

reg  [4:0] state;
reg  [5:0] tos_chunk;            // 16 KB chunks
reg  [6:0] tos_chunks;
reg [23:1] tos_base;
reg        loading_cart;        // second pass of the loader: cartridge ROM at $FA0000
reg  [2:0] cart_skip;           // header bytes skipped (Hatari .stc files may carry 4)
reg [12:0] word_idx;
reg  [5:0] pace;
reg  [4:0] hdr_cnt;
reg  [8:0] byte_idx;
reg  [1:0] phase;               // RAM reads: set address, wait, use q
reg        hd_cur;              // the request being served is an ACSI one
reg  [1:0] mount_seen;
reg  [1:0] mount_pending;
reg  [3:0] mount_cnt;
reg        mount_drive;

// FPGA power-up values; the request/ack toggles must start equal
initial begin
	state = S_BOOT;
	req_t = 1'b0;
	ack_t_74 = 1'b0;
	estate = E_IDLE;
	retries = 3'd0;
	boot_ready_74 = 1'b0;
	dt_scanning = 1'b0;
	mount_t_74 = 2'b00;
	tos_t_74 = 1'b0;
	cart_size_74 = 32'd0;
	tos_seen = 1'b0;
	tos_pending = 1'b0;
	warm_pending = 1'b0;
	mount_seen = 2'b00;
	mount_pending = 2'b00;
	img_mounted = 2'b00;
	sd_ack = 1'b0;
	hd_ack = 1'b0;
	hd_size0 = 32'd0;
	hd_size1 = 32'd0;
	data_in_strobe = 1'b0;
	data_download = 1'b0;
	tos_done = 1'b0;
	loading_cart = 1'b0;
end

assign load_cart = loading_cart;
assign warm_busy = warm_pending || state == S_WARM;

// progress in percent, as BCD for the loading screen: each finished chunk adds 100 to
// 'pct_acc', which is then divided by the chunk count one subtraction per clock
reg [7:0] pct_acc = 8'd0;
reg       pct_reset, pct_add, pct_full;
function [11:0] bcd_inc3(input [11:0] v);
	bcd_inc3 = v;
	if (v[3:0] != 4'd9) bcd_inc3[3:0] = v[3:0] + 4'd1;
	else begin
		bcd_inc3[3:0] = 4'd0;
		if (v[7:4] != 4'd9) bcd_inc3[7:4] = v[7:4] + 4'd1;
		else begin bcd_inc3[7:4] = 4'd0; bcd_inc3[11:8] = v[11:8] + 4'd1; end
	end
endfunction
always @(posedge clk_32) begin
	if (pct_reset) begin
		load_pct <= 12'h000;
		pct_acc <= 8'd0;
	end else if (pct_full)
		load_pct <= 12'h100;
	else if (pct_add)
		pct_acc <= pct_acc + 8'd100;
	else if (pct_acc >= {1'b0, tos_chunks} && tos_chunks != 0 && load_pct != 12'h100) begin
		pct_acc <= pct_acc - {1'b0, tos_chunks};
		load_pct <= bcd_inc3(load_pct);
	end
end

wire [31:0] cart_size_s = cart_size_74;   // quasi-static: only changes before the reload it triggers
wire [31:0] size_a = size_74[0];   // stable: only changes before its mount toggle crosses
wire [31:0] size_b = size_74[1];

always @(posedge clk_32) begin
	wbuf_we <= 1'b0;
	sd_dout_strobe <= 1'b0;
	pct_reset <= 1'b0;
	pct_add <= 1'b0;
	pct_full <= 1'b0;

	if (mount_s0[2] != mount_seen[0]) begin mount_seen[0] <= mount_s0[2]; mount_pending[0] <= 1'b1; end
	if (mount_s1[2] != mount_seen[1]) begin mount_seen[1] <= mount_s1[2]; mount_pending[1] <= 1'b1; end
	if (tos_s[2] != tos_seen) begin tos_seen <= tos_s[2]; tos_pending <= 1'b1; end
	// while TOS is loading the ST is in reset anyway: a restart then would just load twice
	if (cold_req && tos_done) tos_pending <= 1'b1;
	if (warm_req && tos_done) warm_pending <= 1'b1;

	case (state)
	S_BOOT: begin
		tos_done <= 1'b0;
		warm_pending <= 1'b0;   // the boot clears low RAM anyway
		data_download <= 1'b0;
		if (boot_s[2]) begin
			pct_reset <= 1'b1;
			loading_cart <= 1'b0;
			cart_skip <= 3'd0;
			tos_chunk <= 6'd0;
			tos_chunks <= 7'd1; // refined once the header is parsed
			data_download <= 1'b1;
			word_idx <= 13'd0;
			pace <= 6'd0;
			state <= S_CLEAR;
		end
	end

	// Every boot is a cold boot: zero $0-$FFF so TOS finds no memvalid magic
	// ($420/$43A/$51A) and sizes memory again after a RAM or machine change.
	S_CLEAR: begin
		pace <= pace + 6'd1;
		if (pace == 6'd0) begin
			data_in_reg <= 16'h0000;
			data_addr <= {10'd0, word_idx};
		end
		if (pace == 6'd4) data_in_strobe <= ~data_in_strobe;
		if (pace == STROBE_GAP) begin
			pace <= 6'd0;
			word_idx <= word_idx + 13'd1;
			if (word_idx == 13'd2047) state <= S_TOS_REQ;
		end
	end

	// Warm reset: zero resvalid/resvector ($426-$42D) so TOS boots instead of jumping
	// into a program's reset handler; memvalid stays, so memory is not sized again.
	S_WARM: begin
		pace <= pace + 6'd1;
		if (pace == 6'd0) begin
			data_in_reg <= 16'h0000;
			data_addr <= 23'h213 + {21'd0, word_idx[1:0]};
		end
		if (pace == 6'd4) data_in_strobe <= ~data_in_strobe;
		if (pace == STROBE_GAP) begin
			pace <= 6'd0;
			word_idx <= word_idx + 13'd1;
			if (word_idx == 13'd3) begin
				data_download <= 1'b0;
				state <= S_IDLE;
			end
		end
	end

	// ---------------- TOS: 16 KB chunks into ST ROM space ----------------
	S_TOS_REQ: if (!req_busy) begin
		req_write      <= 1'b0;
		req_slot       <= loading_cart ? SLOT_CART : SLOT_TOS;
		req_offset     <= {12'd0, tos_chunk, 14'd0} + {29'd0, cart_skip};
		req_length     <= 32'd16384;
		req_bridgeaddr <= RBUF_ADDR;
		req_t          <= ~req_t;
		state          <= S_TOS_WAIT;
	end

	S_TOS_WAIT: if (!req_busy) begin
		word_idx <= 13'd0;
		hdr_cnt <= 5'd0;
		rbuf_raddr <= 14'd9;
		state <= (tos_chunk == 0 && !loading_cart) ? S_TOS_HDR : S_TOS_HI;
	end

	// os_base (long at offset 8): byte 9 is $FC for a 192 KB TOS at $FC0000, else it is a
	// 256 KB TOS at $E00000. rbuf_q is sampled 3 clocks after the address is set.
	S_TOS_HDR: begin
		hdr_cnt <= hdr_cnt + 5'd1;
		rbuf_raddr <= 14'd9;
		if (hdr_cnt == 5'd3) begin
			if (rbuf_q == 8'hFC) begin tos_base <= 23'h7E0000; tos_chunks <= 7'd12; end
			else                 begin tos_base <= 23'h700000; tos_chunks <= 7'd16; end
			state <= S_TOS_HI;
		end
	end

	// rbuf_q is valid two clocks after rbuf_raddr changes
	S_TOS_HI: begin
		rbuf_raddr <= {word_idx, 1'b0};
		pace <= 6'd0;
		state <= S_TOS_LO;
	end

	S_TOS_LO: begin
		pace <= pace + 6'd1;
		if (pace == 6'd0) rbuf_raddr <= {word_idx, 1'b1};
		if (pace == 6'd1) data_in_reg[15:8] <= rbuf_q;
		if (pace == 6'd2) begin
			data_in_reg[7:0] <= rbuf_q;
			data_addr <= tos_base + {4'd0, tos_chunk, word_idx};
			state <= S_TOS_PACE;
		end
	end

	// the ST side samples the strobe once per 2 MHz bus slot; stay well below that
	S_TOS_PACE: begin
		pace <= pace + 6'd1;
		if (pace == 6'd4) data_in_strobe <= ~data_in_strobe;
		if (pace == STROBE_GAP) begin
			word_idx <= word_idx + 13'd1;
			if (word_idx == 13'd8191) begin
				tos_chunk <= tos_chunk + 6'd1;
				pct_add <= 1'b1;
				state <= S_TOS_REQ;
				if ({1'b0, tos_chunk} + 7'd1 == tos_chunks) begin
					pct_full <= 1'b1;
					if (!loading_cart && cart_size_s != 0) begin
						// then the cartridge: up to 128 KB at $FA0000 (word $7D0000)
						loading_cart <= 1'b1;
						pct_reset <= 1'b1;
						cart_skip <= (cart_size_s == 32'd131076) ? 3'd4 : 3'd0;
						tos_base <= 23'h7D0000;
						tos_chunk <= 6'd0;
						tos_chunks <= (cart_size_s >= 32'd131072) ? 7'd8 : {4'd0, cart_size_s[16:14]} + {6'd0, |cart_size_s[13:0]};
					end else begin
						data_download <= 1'b0;
						tos_done <= 1'b1;
						state <= S_IDLE;
					end
				end
			end else
				state <= S_TOS_HI;
		end
	end

	// ---------------- FDC ----------------
	S_IDLE: begin
		sd_ack <= 1'b0;
		hd_ack <= 1'b0;
		if (tos_pending) begin
			// reload TOS; tos_done low holds the ST in reset meanwhile
			tos_pending <= 1'b0;
			state <= S_BOOT;
		end else if (warm_pending) begin
			warm_pending <= 1'b0;
			data_download <= 1'b1;
			word_idx <= 13'd0;
			pace <= 6'd0;
			state <= S_WARM;
		end else if (mount_pending[0] || mount_pending[1]) begin
			mount_drive <= !mount_pending[0];
			img_size <= mount_pending[0] ? size_a : size_b;
			mount_cnt <= 4'd0;
			state <= S_MOUNT;
		end else if (|sd_rd && !req_busy) begin
			sd_ack <= 1'b1;
			hd_cur <= 1'b0;
			req_write      <= 1'b0;
			req_slot       <= sd_rd[1] ? SLOT_FDD_B : SLOT_FDD_A;
			req_offset     <= {sd_lba[22:0], 9'd0};
			req_length     <= 32'd512;
			req_bridgeaddr <= RBUF_ADDR;
			req_t          <= ~req_t;
			state <= S_FD_RD_WAIT;
		end else if (|sd_wr && !req_busy) begin
			sd_ack <= 1'b1;
			hd_cur <= 1'b0;
			req_slot   <= sd_wr[1] ? SLOT_FDD_B : SLOT_FDD_A;
			req_offset <= {sd_lba[22:0], 9'd0};
			byte_idx <= 9'd0;
			phase <= 2'd0;
			state <= S_FD_WR_DATA;
		end else if (|hd_rd && !req_busy) begin
			hd_ack <= 1'b1;
			hd_cur <= 1'b1;
			req_write      <= 1'b0;
			req_slot       <= hd_rd[1] ? SLOT_HDD_1 : SLOT_HDD_0;
			req_offset     <= {hd_lba[22:0], 9'd0};
			req_length     <= 32'd512;
			req_bridgeaddr <= RBUF_ADDR;
			req_t          <= ~req_t;
			state <= S_FD_RD_WAIT;
		end else if (|hd_wr && !req_busy) begin
			hd_ack <= 1'b1;
			hd_cur <= 1'b1;
			req_slot   <= hd_wr[1] ? SLOT_HDD_1 : SLOT_HDD_0;
			req_offset <= {hd_lba[22:0], 9'd0};
			byte_idx <= 9'd0;
			phase <= 2'd0;
			state <= S_FD_WR_DATA;
		end
	end

	S_MOUNT: begin
		mount_cnt <= mount_cnt + 4'd1;
		if (mount_cnt == 4'd1) img_mounted[mount_drive] <= 1'b1;
		if (mount_cnt == 4'd8) begin
			img_mounted <= 2'b00;
			mount_pending[mount_drive] <= 1'b0;
			state <= S_IDLE;
		end
	end

	S_FD_RD_WAIT: if (!req_busy) begin
		byte_idx <= 9'd0;
		phase <= 2'd0;
		state <= S_FD_RD_DATA;
	end

	// 3 clocks per byte: address, RAM latch, use q
	S_FD_RD_DATA: begin
		phase <= phase + 2'd1;
		if (phase == 2'd0) rbuf_raddr <= {5'd0, byte_idx};
		if (phase == 2'd2) begin
			phase <= 2'd0;
			sd_buff_addr <= byte_idx;
			sd_dout <= rbuf_q;
			sd_dout_strobe <= 1'b1;
			byte_idx <= byte_idx + 9'd1;
			if (byte_idx == 9'd511) state <= S_FD_END;
		end
	end

	// the FDC buffer's sd_din is registered: valid two clocks after sd_buff_addr
	S_FD_WR_DATA: begin
		phase <= phase + 2'd1;
		if (phase == 2'd0) sd_buff_addr <= byte_idx;
		if (phase == 2'd2) begin
			phase <= 2'd0;
			wbuf_we <= 1'b1;
			wbuf_waddr <= byte_idx;
			wbuf_wdata <= hd_cur ? hd_din : sd_din;
			byte_idx <= byte_idx + 9'd1;
			if (byte_idx == 9'd511) begin
				req_write      <= 1'b1;
				req_length     <= 32'd512;
				req_bridgeaddr <= WBUF_ADDR;
				req_t          <= ~req_t;
				state <= S_FD_WR_WAIT;
			end
		end
	end

	S_FD_WR_WAIT: if (!req_busy) state <= S_FD_END;

	// dropping the ack completes the FDC's (or ACSI's) request
	S_FD_END: begin
		sd_ack <= 1'b0;
		hd_ack <= 1'b0;
		state <= S_IDLE;
	end

	default: state <= S_BOOT;
	endcase
end

endmodule

`default_nettype wire
