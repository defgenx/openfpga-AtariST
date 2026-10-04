//
// Atari ST/STE core top level for the Analogue Pocket
//
// Instantiated by the real top-level: apf_top. Wraps MiSTery's atarist_sdram;
// see docs/architecture.md for how the APF side maps onto the MiST interfaces.
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;

// PSRAM and SRAM are unused: ST RAM and TOS live in SDRAM
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ Clocks ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire clk_32, clk_32_90, clk_96, clk_96_sd, clk_128, clk_2;
wire pll_core_locked;
wire pll_core_locked_s;
synch_3 s_lock(pll_core_locked, pll_core_locked_s, clk_74a);

pll_st pll (
	.refclk    ( clk_74a ),
	.rst       ( 1'b0 ),
	.clk_32    ( clk_32 ),
	.clk_32_90 ( clk_32_90 ),
	.clk_96    ( clk_96 ),
	.clk_96_sd ( clk_96_sd ),
	.clk_128   ( clk_128 ),
	.clk_2     ( clk_2 ),
	.locked    ( pll_core_locked )
);

// 2.4576 MHz MFP clock enable from clk_32 (as in mist_top.sv)
localparam SYSTEM_CLOCK = 32'd32_084_988;
localparam MFP_CLOCK    = 32'd2_457_600;
reg [31:0] clk_cnt_mfp = 0;
reg        clk_mfp_en;
always @(posedge clk_32) begin
	clk_mfp_en <= 1'b0;
	if (clk_cnt_mfp < SYSTEM_CLOCK)
		clk_cnt_mfp <= clk_cnt_mfp + MFP_CLOCK;
	else begin
		clk_cnt_mfp <= clk_cnt_mfp - SYSTEM_CLOCK + MFP_CLOCK;
		clk_mfp_en <= 1'b1;
	end
end

/* ------------------------------------------------------------------------------ */
/* --------------------------- Host/target commands ----------------------------- */
/* ------------------------------------------------------------------------------ */

    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;

    wire            status_boot_done = pll_core_locked_s;
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;

    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported = 0;
    wire    [31:0]  savestate_addr = 0;
    wire    [31:0]  savestate_size = 0;
    wire    [31:0]  savestate_maxloadsize = 0;

    wire            savestate_start;
    wire            savestate_start_ack = 0;
    wire            savestate_start_busy = 0;
    wire            savestate_start_ok = 0;
    wire            savestate_start_err = 0;

    wire            savestate_load;
    wire            savestate_load_ack = 0;
    wire            savestate_load_busy = 0;
    wire            savestate_load_ok = 0;
    wire            savestate_load_err = 0;

    wire            osnotify_inmenu;

    wire            target_dataslot_read;
    wire            target_dataslot_write;
    wire            target_dataslot_getfile = 0;
    wire            target_dataslot_openfile = 0;

    wire            target_dataslot_ack;
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    wire    [15:0]  target_dataslot_id;
    wire    [31:0]  target_dataslot_slotoffset;
    wire    [31:0]  target_dataslot_bridgeaddr;
    wire    [31:0]  target_dataslot_length;

    wire    [31:0]  target_buffer_param_struct;
    wire    [31:0]  target_buffer_resp_struct;

    wire    [9:0]   datatable_addr;
    wire            datatable_wren = 0;
    wire    [31:0]  datatable_data = 0;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------- Bridge read multiplexer ------------------------- */
/* ------------------------------------------------------------------------------ */

wire [31:0] media_bridge_rd_data;
reg  [31:0] cfg_bridge_rd_data;

always @(*) begin
	casex (bridge_addr)
	32'h10xxxxxx: bridge_rd_data <= media_bridge_rd_data;
	32'h80xxxxxx: bridge_rd_data <= cfg_bridge_rd_data;
	32'hF8xxxxxx: bridge_rd_data <= cmd_bridge_rd_data;
	default:      bridge_rd_data <= 0;
	endcase
end

/* ------------------------------------------------------------------------------ */
/* -------------------------- Settings (interact.json) -------------------------- */
/* ------------------------------------------------------------------------------ */
// One register per menu entry; addresses must match interact.json.

reg        cfg_reset_t;          // toggles on "Reset ST"
reg  [1:0] cfg_model    = 2'd0;  // 0 ST, 1 STE, 2 Mega STE
reg  [2:0] cfg_mem      = 3'd1;  // 0 512K, 1 1M, 2 2M, 3 4M, 4 8M, 5 14M
reg        cfg_mono     = 1'b0;
reg        cfg_blitter  = 1'b0;
reg        cfg_stereo   = 1'b0;
reg  [1:0] cfg_wp       = 2'b11; // write protect A/B
reg        cfg_borders  = 1'b1;
reg        cfg_padmouse = 1'b0;
reg        cfg_cpu020   = 1'b0;

always @(posedge clk_74a) begin
	if (bridge_wr && bridge_addr[31:8] == 24'h800000) begin
		case (bridge_addr[7:0])
		8'h00: cfg_reset_t  <= ~cfg_reset_t;
		8'h04: cfg_model    <= bridge_wr_data[1:0];
		8'h08: cfg_mem      <= bridge_wr_data[2:0];
		8'h0C: cfg_mono     <= bridge_wr_data[0];
		8'h10: cfg_blitter  <= bridge_wr_data[0];
		8'h14: cfg_stereo   <= bridge_wr_data[0];
		8'h18: cfg_wp       <= bridge_wr_data[1:0];
		8'h1C: cfg_borders  <= bridge_wr_data[0];
		8'h20: cfg_padmouse <= bridge_wr_data[0];
		8'h24: cfg_cpu020   <= bridge_wr_data[0];
		default: ;
		endcase
	end
	case (bridge_addr[7:0])
	8'h04: cfg_bridge_rd_data <= cfg_model;
	8'h08: cfg_bridge_rd_data <= cfg_mem;
	8'h0C: cfg_bridge_rd_data <= cfg_mono;
	8'h10: cfg_bridge_rd_data <= cfg_blitter;
	8'h14: cfg_bridge_rd_data <= cfg_stereo;
	8'h18: cfg_bridge_rd_data <= cfg_wp;
	8'h1C: cfg_bridge_rd_data <= cfg_borders;
	8'h20: cfg_bridge_rd_data <= cfg_padmouse;
	8'h24: cfg_bridge_rd_data <= cfg_cpu020;
	default: cfg_bridge_rd_data <= 0;
	endcase
end

// quasi-static settings, synchronised as a bundle
wire [14:0] cfg_s;
synch_3 #(.WIDTH(15)) s_cfg(
	{cfg_reset_t, cfg_model, cfg_mem, cfg_mono, cfg_blitter, cfg_stereo, cfg_wp, cfg_borders, cfg_padmouse, cfg_cpu020},
	cfg_s, clk_32);
wire       reset_t_32  = cfg_s[14];
wire [1:0] model_32    = cfg_s[13:12];
wire [2:0] mem_32      = cfg_s[11:9];
wire       mono_32     = cfg_s[8];
wire       blitter_32  = cfg_s[7];
wire       stereo_32   = cfg_s[6];
wire [1:0] wp_32       = cfg_s[5:4];
wire       borders_32  = cfg_s[3];
wire       padmouse_32 = cfg_s[2];
wire       cpu020_32   = cfg_s[1];

/* ------------------------------------------------------------------------------ */
/* ------------------------------------- Reset ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire reset_n_s;
synch_3 s_rst(reset_n, reset_n_s, clk_32);

wire tos_done;

// Machine-shape changes (model, RAM, CPU, monitor) need a reset to take effect.
reg  [6:0] machine_d = 0;
reg        reset_t_d = 0;
reg [15:0] reset_hold = 0;
wire [6:0] machine = {model_32, mem_32, cpu020_32, mono_32};

always @(posedge clk_32) begin
	machine_d <= machine;
	reset_t_d <= reset_t_32;
	if (reset_hold != 0) reset_hold <= reset_hold - 16'd1;
	if (machine != machine_d || reset_t_32 != reset_t_d) reset_hold <= 16'hFFFF;
end

wire st_reset = ~reset_n_s | ~tos_done | (reset_hold != 0);

wire [31:0] system_ctrl = {
	1'b0,               // 31
	1'b0,               // 30 cubase dongle
	1'b0,               // 29 blend
	1'b0,               // 28 viking
	2'b00,              // 27:26 usb redirection
	1'b0,               // 25 ethernec
	model_32 == 2'd2,   // 24 Mega STE
	model_32 == 2'd1,   // 23 STE
	stereo_32,          // 22 PSG stereo
	2'b00,              // 21:20 scanlines
	blitter_32,         // 19 blitter (always on for STE)
	1'b0,               // 18
	8'h00,              // 17:10 ACSI devices
	1'b0,               // 9
	mono_32,            // 8 mono monitor
	wp_32,              // 7:6 floppy write protect
	cpu020_32 ? 2'b11 : 2'b00, // 5:4 CPU
	mem_32,             // 3:1 RAM size
	st_reset            // 0 reset
};

/* ------------------------------------------------------------------------------ */
/* --------------------------- TOS and floppy images ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire        data_download;
wire [23:1] data_addr;
wire [15:0] data_in_reg;
wire        data_in_strobe;

wire  [1:0] img_mounted;
wire [31:0] img_size;
wire [31:0] sd_lba;
wire  [1:0] sd_rd, sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_dout, sd_din;
wire        sd_dout_strobe;

st_media media (
	.clk_74a                    ( clk_74a ),
	.clk_32                     ( clk_32 ),

	.bridge_addr                ( bridge_addr ),
	.bridge_wr                  ( bridge_wr ),
	.bridge_wr_data             ( bridge_wr_data ),
	.bridge_rd_data             ( media_bridge_rd_data ),

	.target_dataslot_read       ( target_dataslot_read ),
	.target_dataslot_write      ( target_dataslot_write ),
	.target_dataslot_id         ( target_dataslot_id ),
	.target_dataslot_slotoffset ( target_dataslot_slotoffset ),
	.target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
	.target_dataslot_length     ( target_dataslot_length ),
	.target_dataslot_done       ( target_dataslot_done ),

	.dataslot_update            ( dataslot_update ),
	.dataslot_update_id         ( dataslot_update_id ),
	.dataslot_update_size       ( dataslot_update_size ),
	.dataslot_allcomplete       ( dataslot_allcomplete ),
	.datatable_addr             ( datatable_addr ),
	.datatable_q                ( datatable_q ),

	.tos_done                   ( tos_done ),
	.data_download              ( data_download ),
	.data_addr                  ( data_addr ),
	.data_in_reg                ( data_in_reg ),
	.data_in_strobe             ( data_in_strobe ),

	.img_mounted                ( img_mounted ),
	.img_size                   ( img_size ),
	.sd_lba                     ( sd_lba ),
	.sd_rd                      ( sd_rd ),
	.sd_wr                      ( sd_wr ),
	.sd_ack                     ( sd_ack ),
	.sd_buff_addr               ( sd_buff_addr ),
	.sd_dout                    ( sd_dout ),
	.sd_dout_strobe             ( sd_dout_strobe ),
	.sd_din                     ( sd_din )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- Controllers ------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [31:0] cont1_key_s, cont2_key_s, cont3_key_s, cont4_key_s;
wire [31:0] cont1_joy_s, cont3_joy_s, cont4_joy_s;
wire [15:0] cont3_trig_s, cont4_trig_s;
synch_3 #(.WIDTH(32)) s_c1k(cont1_key, cont1_key_s, clk_32);
synch_3 #(.WIDTH(32)) s_c2k(cont2_key, cont2_key_s, clk_32);
synch_3 #(.WIDTH(32)) s_c3k(cont3_key, cont3_key_s, clk_32);
synch_3 #(.WIDTH(32)) s_c4k(cont4_key, cont4_key_s, clk_32);
synch_3 #(.WIDTH(32)) s_c3j(cont3_joy, cont3_joy_s, clk_32);
synch_3 #(.WIDTH(32)) s_c4j(cont4_joy, cont4_joy_s, clk_32);
synch_3 #(.WIDTH(16)) s_c3t(cont3_trig, cont3_trig_s, clk_32);
synch_3 #(.WIDTH(32)) s_c1j(cont1_joy, cont1_joy_s, clk_32);
synch_3 #(.WIDTH(16)) s_c4t(cont4_trig, cont4_trig_s, clk_32);

// MiST joystick encoding: [0] right [1] left [2] down [3] up [4] fire [5] fire 2
function [15:0] pad2joy(input [31:0] k);
	pad2joy = {10'd0, k[5], k[4], k[0], k[1], k[2], k[3]};
endfunction

// Handheld controls follow the Pocket Amiga core: Select opens the on-screen
// keyboard, Start toggles mouse mode (D-pad moves, A/L = left, B/R = right click).
wire        osk_visible;
wire  [2:0] osk_row;
wire  [3:0] osk_col;
wire  [2:0] osk_mods;
wire  [7:0] osk_key;
wire        osk_mouse_toggle;

osk_ctrl osk_ctrl (
	.clk          ( clk_32 ),
	.reset        ( ~reset_n_s ),
	.pad          ( cont1_key_s[15:0] ),
	.visible      ( osk_visible ),
	.cur_row      ( osk_row ),
	.cur_col      ( osk_col ),
	.mods         ( osk_mods ),
	.key          ( osk_key ),
	.mouse_toggle ( osk_mouse_toggle )
);

// mouse mode: the menu setting is the default, Start flips it
reg mouse_mode_flip = 1'b0;
reg padmouse_d = 1'b0;
always @(posedge clk_32) begin
	padmouse_d <= padmouse_32;
	if (padmouse_32 != padmouse_d) mouse_mode_flip <= 1'b0;
	else if (osk_mouse_toggle)      mouse_mode_flip <= ~mouse_mode_flip;
end
wire pad_mouse_mode = (padmouse_32 ^ mouse_mode_flip) & ~osk_visible;

// pad 1 drives the ST joystick port unless it is the mouse or typing on the keyboard;
// pad 2 drives the mouse port (port 0), which the IKBD shares with the mouse.
wire [15:0] joy1 = (padmouse_32 ^ mouse_mode_flip) | osk_visible ? 16'd0 : pad2joy(cont1_key_s);
wire [15:0] joy0 = pad2joy(cont2_key_s);

// keys typed by pad 1 (HID usages): X = Space, Y = Return, plus the on-screen keyboard
wire [7:0] pad_space  = cont1_key_s[6] ? 8'h2C : 8'h00;
wire [7:0] pad_return = cont1_key_s[7] ? 8'h28 : 8'h00;
wire [39:0] pad_keys = {
	osk_key,
	osk_mods[0] ? 8'hE0 : 8'h00,
	osk_mods[1] ? 8'hE1 : 8'h00,
	osk_mods[2] ? 8'hE2 : 8'h00,
	osk_visible ? 8'h00 : (cont1_key_s[6] ? pad_space : pad_return)
};

// Dock keyboard on player 3, Dock mouse on player 4 (type nibbles 4 and 5)
wire        kbd_present   = cont3_key_s[31:28] == 4'h4;
wire        mouse_present = cont4_key_s[31:28] == 4'h5;

// Dock mouse: new report when the little-endian counter in cont4_key[15:0] changes.
// Motion bits are sampled a few clocks later so all synchronised bits have settled.
reg  [15:0] mouse_cnt_d;
reg   [3:0] mouse_settle;
reg         dock_mouse_event;
reg  signed [15:0] dock_dx, dock_dy;
always @(posedge clk_32) begin
	dock_mouse_event <= 1'b0;
	mouse_cnt_d <= cont4_key_s[15:0];
	if (mouse_present && cont4_key_s[15:0] != mouse_cnt_d) mouse_settle <= 4'd8;
	else if (mouse_settle != 0) begin
		mouse_settle <= mouse_settle - 4'd1;
		if (mouse_settle == 4'd1) begin
			dock_dx <= {cont4_joy_s[7:0], cont4_joy_s[15:8]};
			dock_dy <= {cont4_trig_s[7:0], cont4_trig_s[15:8]};
			dock_mouse_event <= 1'b1;
		end
	end
end

// Pad mouse: D-pad moves, speeds up after ~0.5 s held. A Dock analog controller's
// left stick (player 1, type 3) moves the mouse in any mode, as in the Amiga core.
wire        stick_present = cont1_key_s[31:28] == 4'h3;
wire signed [8:0] stick_x = {1'b0, cont1_joy_s[7:0]}  - 9'sd128;
wire signed [8:0] stick_y = {1'b0, cont1_joy_s[15:8]} - 9'sd128;
wire        stick_moved = stick_present && (stick_x > 9'sd24 || stick_x < -9'sd24 || stick_y > 9'sd24 || stick_y < -9'sd24);
reg  [16:0] padm_tick;
reg   [4:0] padm_hold;
reg         pad_mouse_event;
reg  signed [15:0] pad_dx, pad_dy;
wire [3:0]  pad_dir = cont1_key_s[3:0];
always @(posedge clk_32) begin
	pad_mouse_event <= 1'b0;
	padm_tick <= padm_tick + 17'd1;
	if (padm_tick == 0) begin   // ~245 Hz
		if (pad_mouse_mode && pad_dir != 0) begin
			if (padm_hold != 5'd31) padm_hold <= padm_hold + 5'd1;
			pad_dx <= pad_dir[3] ? (padm_hold[4] ? 16'sd4 : 16'sd1) : pad_dir[2] ? (padm_hold[4] ? -16'sd4 : -16'sd1) : 16'sd0;
			pad_dy <= pad_dir[1] ? (padm_hold[4] ? 16'sd4 : 16'sd1) : pad_dir[0] ? (padm_hold[4] ? -16'sd4 : -16'sd1) : 16'sd0;
			pad_mouse_event <= 1'b1;
		end else if (stick_moved && !osk_visible) begin
			pad_dx <= {{11{stick_x[8]}}, stick_x[8:4]};   // stick / 16, sign-extended
			pad_dy <= {{11{stick_y[8]}}, stick_y[8:4]};
			pad_mouse_event <= 1'b1;
		end else
			padm_hold <= 5'd0;
	end
end

wire [2:0] mouse_buttons =
	(mouse_present ? cont4_joy_s[18:16] : 3'b000) |
	(pad_mouse_mode ? {1'b0, cont1_key_s[5] | cont1_key_s[9], cont1_key_s[4] | cont1_key_s[8]} : 3'b000) |
	(stick_present && !osk_visible ? {1'b0, cont1_key_s[9], cont1_key_s[8]} : 3'b000);

wire ps2_kbd_clk, ps2_kbd_data, ps2_mouse_clk, ps2_mouse_data;

hid_ps2 hid (
	.clk           ( clk_32 ),
	.reset         ( ~reset_n_s ),
	.kbd_present   ( kbd_present ),
	.kbd_codes     ( {cont3_joy_s, cont3_trig_s} ),
	.kbd_mods      ( cont3_key_s[15:8] ),
	.pad_keys      ( pad_keys ),
	.mouse_event   ( dock_mouse_event | pad_mouse_event ),
	.mouse_dx      ( dock_mouse_event ? dock_dx : pad_dx ),
	.mouse_dy      ( dock_mouse_event ? dock_dy : pad_dy ),
	.mouse_buttons ( mouse_buttons ),
	.kbd_clk       ( ps2_kbd_clk ),
	.kbd_data      ( ps2_kbd_data ),
	.mouse_clk     ( ps2_mouse_clk ),
	.mouse_data    ( ps2_mouse_data )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- RTC --------------------------------------- */
/* ------------------------------------------------------------------------------ */
// MiSTery format (BCD): [7:0] sec [15:8] min [23:16] hour [31:24] day
// [39:32] month [47:40] year (00-99) [55:48] weekday. Captured once at boot.

reg [63:0] rtc_74;
always @(posedge clk_74a)
	if (rtc_valid) rtc_74 <= {8'h00, 8'h00, rtc_date_bcd[23:16], rtc_date_bcd[15:8], rtc_date_bcd[7:0],
	                          rtc_time_bcd[23:16], rtc_time_bcd[15:8], rtc_time_bcd[7:0]};
wire [63:0] rtc;
synch_3 #(.WIDTH(64)) s_rtc(rtc_74, rtc, clk_32);

/* ------------------------------------------------------------------------------ */
/* --------------------------------- The Atari ST ------------------------------- */
/* ------------------------------------------------------------------------------ */

wire  [3:0] st_r, st_g, st_b;
wire        st_hsync_n, st_vsync_n, st_hblank_n, st_vblank_n, st_blank_n;
wire        st_monomode;
wire [14:0] audio_mix_l, audio_mix_r;

atarist_sdram #(1'b1, 1'b1) atarist (
	.clk_96              ( clk_96 ),
	.clk_32              ( clk_32 ),
	.clk_128             ( clk_128 ),
	.clk_2               ( clk_2 ),
	.clk_mfp             ( clk_mfp_en ),
	.porb                ( pll_core_locked ),
	.system_ctrl         ( system_ctrl ),

	.r                   ( st_r ),
	.g                   ( st_g ),
	.b                   ( st_b ),
	.hsync_n             ( st_hsync_n ),
	.vsync_n             ( st_vsync_n ),
	.monomode            ( st_monomode ),
	.blank_n             ( st_blank_n ),
	.hblank_n            ( st_hblank_n ),
	.vblank_n            ( st_vblank_n ),

	.viking_active       ( ),
	.viking_r            ( ),
	.viking_g            ( ),
	.viking_b            ( ),
	.viking_hs           ( ),
	.viking_vs           ( ),
	.viking_hb           ( ),
	.viking_vb           ( ),

	.audio_mix_l         ( audio_mix_l ),
	.audio_mix_r         ( audio_mix_r ),

	.midi_out_strobe     ( ),
	.midi_out            ( ),
	.midi_rx             ( 1'b1 ),
	.midi_tx             ( ),

	.parallel_in_strobe  ( 1'b1 ),
	.parallel_in         ( 8'hff ),
	.parallel_out_strobe ( ),
	.parallel_out        ( ),
	.parallel_printer_busy ( 1'b1 ),

	.serial_redirect     ( 1'b1 ),
	.serial_data_out_available ( ),
	.serial_strobe_out   ( 1'b0 ),
	.serial_data_out     ( ),
	.serial_status_out   ( ),
	.serial_strobe_in    ( 1'b0 ),
	.serial_data_in      ( 8'h00 ),
	.uart_ctsb           ( 1'b0 ),
	.uart_rtsb           ( ),
	.uart_rx             ( 1'b1 ),
	.uart_tx             ( ),

	.data_in_strobe_rom  ( data_in_strobe ),
	.data_in_strobe_acsi ( 1'b0 ),
	.data_in_reg         ( data_in_reg ),
	.data_addr           ( data_addr ),
	.data_download       ( data_download ),

	.data_out_strobe     ( 1'b0 ),
	.data_out_reg        ( ),
	.dma_ack             ( 1'b0 ),
	.dma_status          ( 8'h00 ),
	.dma_nak             ( 1'b0 ),
	.dma_status_in       ( ),
	.dma_status_index    ( 4'd0 ),

	.img_mounted         ( img_mounted ),
	.img_wp              ( wp_32 ),
	.img_size            ( img_size ),
	.sd_lba              ( sd_lba ),
	.sd_rd               ( sd_rd ),
	.sd_wr               ( sd_wr ),
	.sd_ack              ( sd_ack ),
	.sd_buff_addr        ( sd_buff_addr ),
	.sd_dout             ( sd_dout ),
	.sd_din              ( sd_din ),
	.sd_dout_strobe      ( sd_dout_strobe ),
	.LED                 ( ),

	.eth_status          ( ),
	.eth_mac_begin       ( 1'b0 ),
	.eth_mac_strobe      ( 1'b0 ),
	.eth_mac_byte        ( 8'h00 ),
	.eth_tx_read_begin   ( 1'b0 ),
	.eth_tx_read_strobe  ( 1'b0 ),
	.eth_tx_read_byte    ( ),
	.eth_rx_write_begin  ( 1'b0 ),
	.eth_rx_write_strobe ( 1'b0 ),
	.eth_rx_write_byte   ( 8'h00 ),

	.ps2_kbd_clk         ( ps2_kbd_clk ),
	.ps2_kbd_data        ( ps2_kbd_data ),
	.ps2_mouse_clk       ( ps2_mouse_clk ),
	.ps2_mouse_data      ( ps2_mouse_data ),

	.joy0                ( joy0 ),
	.joy1                ( joy1 ),

	.rtc                 ( rtc ),

	// sdram.v drives CS as part of its command; the Pocket SDRAM has CS tied low,
	// and every CMD_INHIBIT it issues is a NOP once CS is dropped.
	.SDRAM_DQ            ( dram_dq ),
	.SDRAM_A             ( dram_a ),
	.SDRAM_DQML          ( dram_dqm[0] ),
	.SDRAM_DQMH          ( dram_dqm[1] ),
	.SDRAM_nWE           ( dram_we_n ),
	.SDRAM_nCAS          ( dram_cas_n ),
	.SDRAM_nRAS          ( dram_ras_n ),
	.SDRAM_nCS           ( ),
	.SDRAM_BA            ( dram_ba )
);

assign dram_cke = 1'b1;
// dram_clk leaves through a DDIO register so its pin delay matches the data pins
pin_ddio_clk dram_clk_ddio (
	.datain_h ( 1'b1 ),
	.datain_l ( 1'b0 ),
	.outclock ( clk_96_sd ),
	.dataout  ( dram_clk )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ Video ----------------------------------- */
/* ------------------------------------------------------------------------------ */

assign video_rgb_clock    = clk_32;

wire [23:0] st_video_rgb;
wire        st_video_de, st_video_skip, st_video_hs, st_video_vs;
assign video_rgb_clock_90 = clk_32_90;

st_video st_video (
	.clk        ( clk_32 ),
	.borders    ( borders_32 ),
	.r          ( st_r ),
	.g          ( st_g ),
	.b          ( st_b ),
	.hsync_n    ( st_hsync_n ),
	.vsync_n    ( st_vsync_n ),
	.blank_n    ( st_blank_n ),
	.monomode   ( st_monomode ),
	.video_rgb  ( st_video_rgb ),
	.video_de   ( st_video_de ),
	.video_skip ( st_video_skip ),
	.video_hs   ( st_video_hs ),
	.video_vs   ( st_video_vs )
);

osk_overlay osk_overlay (
	.clk        ( clk_32 ),
	.visible    ( osk_visible ),
	.cur_row    ( osk_row ),
	.cur_col    ( osk_col ),
	.mods       ( osk_mods ),
	.in_rgb     ( st_video_rgb ),
	.in_de      ( st_video_de ),
	.in_skip    ( st_video_skip ),
	.in_hs      ( st_video_hs ),
	.in_vs      ( st_video_vs ),
	.video_rgb  ( video_rgb ),
	.video_de   ( video_de ),
	.video_skip ( video_skip ),
	.video_hs   ( video_hs ),
	.video_vs   ( video_vs )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ Audio ----------------------------------- */
/* ------------------------------------------------------------------------------ */

sound_i2s #(
	.CHANNEL_WIDTH ( 16 ),
	.SIGNED_INPUT  ( 1 )
) sound_i2s (
	.clk_74a    ( clk_74a ),
	.clk_audio  ( clk_32 ),
	.audio_l    ( {audio_mix_l[14], audio_mix_l} ),
	.audio_r    ( {audio_mix_r[14], audio_mix_r} ),
	.audio_mclk ( audio_mclk ),
	.audio_lrck ( audio_lrck ),
	.audio_dac  ( audio_dac )
);

endmodule

`default_nettype wire
