//
// acsi_ctrl.sv - ACSI hard disk target, the part MiST/MiSTer run on their ARM
//
// MiSTery's dma.v/acsi.v collect the command bytes and run the DMA FIFO; this module
// plays the IO controller: polls for a command, executes it (SCSI-1 subset), moves
// sector data through dma.v's 16-bit strobes and answers with a status byte.
// Sectors come from st_media (HDD slots 3/4). See docs/architecture.md.
//

`default_nettype none

module acsi_ctrl (
	input  wire        clk,            // clk_32
	input  wire        reset,

	// MiSTery dma.v "dio" interface (strobes and acks are toggles)
	input  wire  [7:0] status_in,
	output reg   [3:0] status_index,
	output reg         dma_ack_t,
	output reg   [7:0] dma_status,
	output reg         data_in_t,
	output reg  [15:0] data_in_reg,
	output reg         data_out_t,
	input  wire [15:0] data_out_reg,

	// drives: number of 512-byte blocks, 0 = no image
	input  wire [31:0] blocks0,
	input  wire [31:0] blocks1,

	// sector service from st_media (same handshake as the FDC's sd_* interface)
	output reg   [1:0] hd_rd,
	output reg   [1:0] hd_wr,
	output reg  [31:0] hd_lba,
	input  wire        hd_ack,
	input  wire  [8:0] buff_addr,
	input  wire  [7:0] buff_dout,
	input  wire        buff_wr,
	output reg   [7:0] buff_din      // registered RAM output, valid 1 clock after buff_addr
);

localparam [3:0] STATUS_IDX = 4'd10;   // acsi.v: {target, 4'b0, busy}
localparam PACE = 8'd127;              // clocks per DMA word: keeps the 16-word FIFO in range

/* ------------------------------------------------------------------------ */
/* 512-byte sector buffer, one port: st_media owns it while hd_ack is high,   */
/* this FSM the rest of the time, so a single M10K block is enough.          */
/* ------------------------------------------------------------------------ */
reg  [7:0] buf_mem[512];
reg  [8:0] b_addr;
reg  [7:0] b_wdata;
reg        b_we;
wire [8:0] m_addr  = hd_ack ? buff_addr : b_addr;
wire       m_we    = hd_ack ? buff_wr   : b_we;
wire [7:0] m_wdata = hd_ack ? buff_dout : b_wdata;
reg  [7:0] m_q;
always @(posedge clk) begin
	if (m_we) buf_mem[m_addr] <= m_wdata;
	m_q <= buf_mem[m_addr];
end
wire [7:0] b_q = m_q;
always @(*) buff_din = m_q;

/* ------------------------------------------------------------------------ */
/* Command state                                                             */
/* ------------------------------------------------------------------------ */
reg  [7:0] cmd[10];
reg  [2:0] target;
reg  [7:0] sense_key[2], sense_asc[2];
wire       drive = target[0];
wire [31:0] blocks = drive ? blocks1 : blocks0;
wire [7:0] op = cmd[0];
wire       is10 = op[5];                         // group 1: 10-byte CDB
wire [31:0] cdb_lba = is10 ? {cmd[2], cmd[3], cmd[4], cmd[5]} : {11'd0, cmd[1][4:0], cmd[2], cmd[3]};
wire [16:0] cdb_len = is10 ? {1'b0, cmd[7], cmd[8]} : (cmd[4] == 0 ? 17'd256 : {9'd0, cmd[4]});
wire [31:0] last_lba = blocks - 32'd1;

// fixed responses, built word by word (index = word number)
function automatic [15:0] resp_word(input [7:0] opc, input [3:0] w, input [31:0] nblk,
                                    input [7:0] skey, input [7:0] sasc, input drv);
	reg [7:0] b[32];
	integer i;
	for (i = 0; i < 32; i = i + 1) b[i] = 8'h00;
	case (opc)
		8'h03: begin   // REQUEST SENSE, extended format
			b[0] = 8'h70; b[2] = skey; b[7] = 8'd10; b[12] = sasc;
		end
		8'h12: begin   // INQUIRY: direct-access, SCSI-1 CCS
			b[2] = 8'h01; b[3] = 8'h01; b[4] = 8'd31;
			{b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]} = "MiSTery ";
			{b[16], b[17], b[18], b[19], b[20], b[21], b[22], b[23]} = "Pocket H";
			{b[24], b[25], b[26], b[27], b[28], b[29], b[30], b[31]} = drv ? "DD 1    " : "DD 0    ";
		end
		8'h1A: begin   // MODE SENSE(6): header + one block descriptor
			b[0] = 8'd11; b[3] = 8'd8;
			{b[5], b[6], b[7]} = nblk[23:0]; b[10] = 8'h02;
		end
		8'h25: begin   // READ CAPACITY: last LBA, block length
			{b[0], b[1], b[2], b[3]} = nblk - 32'd1; b[6] = 8'h02;
		end
		default: ;
	endcase
	resp_word = {b[{w, 1'b0}], b[{w, 1'b1}]};
endfunction

/* ------------------------------------------------------------------------ */
/* FSM                                                                       */
/* ------------------------------------------------------------------------ */
localparam [4:0]
	S_POLL = 0, S_POLL_W = 1, S_CMD = 2, S_CMD_W = 3, S_EXEC = 4,
	S_RESP = 5, S_RESP_W = 6,
	S_RD_REQ = 7, S_RD_WAIT = 8, S_RD_SEND = 9, S_RD_SEND_W = 10,
	S_WR_RECV = 11, S_WR_RECV_W = 12, S_WR_REQ = 13, S_WR_WAIT = 14,
	S_DRAIN = 15, S_ACK = 16, S_SETTLE = 17;

reg  [4:0] state;
reg  [7:0] wait_cnt;
reg  [3:0] cmd_idx;
reg  [7:0] status;
reg  [3:0] resp_words, resp_idx;
reg [31:0] lba;
reg [16:0] count;
reg  [8:0] word_idx;
reg  [1:0] sub;
reg        ack_seen;
reg [11:0] drain_cnt;

task automatic finish(input [7:0] st, input [7:0] key, input [7:0] asc);
	status <= st;
	if (st != 0) begin sense_key[drive] <= key; sense_asc[drive] <= asc; end
	drain_cnt <= 12'd0;
	state <= S_DRAIN;
endtask

initial begin
	state = S_POLL; dma_ack_t = 0; data_in_t = 0; data_out_t = 0; hd_rd = 0; hd_wr = 0;
	sense_key[0] = 0; sense_key[1] = 0; sense_asc[0] = 0; sense_asc[1] = 0;
end

always @(posedge clk) begin
	b_we <= 1'b0;
	if (hd_ack) begin hd_rd <= 2'b00; hd_wr <= 2'b00; end

	if (reset) begin
		state <= S_POLL;
		hd_rd <= 2'b00; hd_wr <= 2'b00;
	end else case (state)

	// ---- wait for acsi.v to flag a complete command ----
	S_POLL: begin status_index <= STATUS_IDX; wait_cnt <= 0; state <= S_POLL_W; end
	S_POLL_W: begin
		wait_cnt <= wait_cnt + 8'd1;
		if (wait_cnt == 8'd3) begin
			if (status_in[0]) begin target <= status_in[7:5]; cmd_idx <= 0; state <= S_CMD; end
			else state <= S_POLL;
		end
	end
	S_CMD: begin status_index <= cmd_idx; wait_cnt <= 0; state <= S_CMD_W; end
	S_CMD_W: begin
		wait_cnt <= wait_cnt + 8'd1;
		if (wait_cnt == 8'd3) begin
			cmd[cmd_idx] <= status_in;
			cmd_idx <= cmd_idx + 4'd1;
			state <= (cmd_idx == 4'd9) ? S_EXEC : S_CMD;
		end
	end

	// ---- decode ----
	S_EXEC: begin
		lba <= cdb_lba;
		count <= cdb_len;
		resp_idx <= 0;
		if (cmd[1][7:5] != 3'd0 && op != 8'h03 && op != 8'h12)
			finish(8'h02, 8'h05, 8'h25);                          // LUN not supported
		else case (op)
			8'h00, 8'h04, 8'h0B, 8'h15, 8'h16, 8'h17, 8'h1B, 8'h1E, 8'h2B, 8'h2F, 8'h35:
				finish(8'h00, 8'h00, 8'h00);                      // nothing to do
			8'h03: begin resp_words <= 4'd15; state <= S_RESP; end      // 32 bytes
			8'h12: begin resp_words <= 4'd15; state <= S_RESP; end
			8'h1A: begin resp_words <= 4'd7;  state <= S_RESP; end      // 16 bytes
			8'h25: begin resp_words <= 4'd7;  state <= S_RESP; end
			8'h08, 8'h28, 8'h0A, 8'h2A: begin
				if (cdb_len == 0) finish(8'h00, 8'h00, 8'h00);
				else if ({1'b0, cdb_lba} + {16'd0, cdb_len} > {1'b0, blocks}) finish(8'h02, 8'h05, 8'h21);
				else begin
					word_idx <= 0; sub <= 0; wait_cnt <= 0;
					state <= op[1] ? S_WR_RECV : S_RD_REQ;      // 0A/2A write
				end
			end
			default: finish(8'h02, 8'h05, 8'h20);               // invalid command
		endcase
	end

	// ---- short fixed responses (padded to whole 16-byte FIFO bursts) ----
	S_RESP: begin
		data_in_reg <= resp_word(op, resp_idx, blocks, sense_key[drive], sense_asc[drive], drive);
		data_in_t <= ~data_in_t;
		wait_cnt <= 0;
		state <= S_RESP_W;
	end
	S_RESP_W: begin
		wait_cnt <= wait_cnt + 8'd1;
		if (wait_cnt == PACE) begin
			resp_idx <= resp_idx + 4'd1;
			if (resp_idx == resp_words) begin
				if (op == 8'h03) begin sense_key[drive] <= 0; sense_asc[drive] <= 0; end
				finish(8'h00, 8'h00, 8'h00);
			end else state <= S_RESP;
		end
	end

	// ---- READ: sector from the card, then 256 words to the DMA ----
	S_RD_REQ: begin
		hd_lba <= lba;
		hd_rd[drive] <= 1'b1;
		ack_seen <= 1'b0;
		state <= S_RD_WAIT;
	end
	S_RD_WAIT: begin
		if (hd_ack) ack_seen <= 1'b1;
		if (ack_seen && !hd_ack) begin word_idx <= 0; sub <= 0; state <= S_RD_SEND; end
	end
	S_RD_SEND: begin   // b_q is valid 2 clocks after b_addr
		sub <= sub + 2'd1;
		case (sub)
			2'd0: b_addr <= {word_idx[7:0], 1'b0};
			2'd1: b_addr <= {word_idx[7:0], 1'b1};
			2'd2: data_in_reg[15:8] <= b_q;
			2'd3: begin
				data_in_reg[7:0] <= b_q;
				data_in_t <= ~data_in_t;
				wait_cnt <= 0;
				state <= S_RD_SEND_W;
			end
		endcase
	end
	S_RD_SEND_W: begin
		wait_cnt <= wait_cnt + 8'd1;
		if (wait_cnt == PACE) begin
			sub <= 0;
			word_idx <= word_idx + 9'd1;
			if (word_idx == 9'd255) begin
				lba <= lba + 32'd1;
				count <= count - 17'd1;
				if (count == 17'd1) finish(8'h00, 8'h00, 8'h00);
				else state <= S_RD_REQ;
			end else state <= S_RD_SEND;
		end
	end

	// ---- WRITE: 256 words from the DMA into the buffer, then to the card ----
	S_WR_RECV: begin   // dma.v presents fifo[rptr] registered; the toggle advances it
		wait_cnt <= wait_cnt + 8'd1;
		if (wait_cnt == PACE) begin
			b_addr <= {word_idx[7:0], 1'b0}; b_wdata <= data_out_reg[15:8]; b_we <= 1'b1;
			state <= S_WR_RECV_W;
		end
	end
	S_WR_RECV_W: begin
		b_addr <= {word_idx[7:0], 1'b1}; b_wdata <= data_out_reg[7:0]; b_we <= 1'b1;
		data_out_t <= ~data_out_t;
		wait_cnt <= 0;
		word_idx <= word_idx + 9'd1;
		state <= (word_idx == 9'd255) ? S_WR_REQ : S_WR_RECV;
	end
	S_WR_REQ: begin
		hd_lba <= lba;
		hd_wr[drive] <= 1'b1;
		ack_seen <= 1'b0;
		state <= S_WR_WAIT;
	end
	S_WR_WAIT: begin
		if (hd_ack) ack_seen <= 1'b1;
		if (ack_seen && !hd_ack) begin
			lba <= lba + 32'd1;
			count <= count - 17'd1;
			word_idx <= 0; wait_cnt <= 0;
			if (count == 17'd1) finish(8'h00, 8'h00, 8'h00);
			else state <= S_WR_RECV;
		end
	end

	// ---- let the FIFO drain into ST RAM, then answer ----
	S_DRAIN: begin
		drain_cnt <= drain_cnt + 12'd1;
		if (drain_cnt == 12'hFFF) state <= S_ACK;
	end
	S_ACK: begin
		dma_status <= status;
		dma_ack_t <= ~dma_ack_t;
		wait_cnt <= 0;
		state <= S_SETTLE;
	end
	S_SETTLE: begin   // acsi.v clears busy a few clocks after the ack
		wait_cnt <= wait_cnt + 8'd1;
		if (wait_cnt == 8'd31) state <= S_POLL;
	end
	default: state <= S_POLL;
	endcase
end

endmodule

`default_nettype wire
