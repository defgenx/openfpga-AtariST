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
// SO / SI carry MIDI OUT / IN (31250 baud) or the RS-232 port's TX / RX (3.3 V levels);
// otherwise the port is left as inputs. SC and SD stay inputs.
assign port_tran_so = link_on_74 ? link_tx_74 : 1'bz;
assign port_tran_so_dir = link_on_74;
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

reg        cfg_reset_t = 1'b0;   // toggles on "Reset ST" (warm)
reg        cfg_cold_t  = 1'b0;   // toggles on "Cold Restart" and "Reset All Settings"
reg  [1:0] cfg_model    = 2'd0;  // 0 ST, 1 STE, 2 Mega STE
reg  [2:0] cfg_mem      = 3'd1;  // 0 512K, 1 1M, 2 2M, 3 4M, 4 8M, 5 14M
reg        cfg_mono     = 1'b0;
reg        cfg_blitter  = 1'b0;
reg        cfg_stereo   = 1'b0;
reg  [1:0] cfg_wp       = 2'b11; // write protect A/B
reg        cfg_borders  = 1'b1;
reg  [1:0] cfg_padmode  = 2'd1;  // 0 joystick, 1 mouse, 2 keys
reg  [1:0] cfg_mouse_spd = 2'd1; // 0 slow, 1 normal, 2 fast (D-pad mouse)
reg        cfg_stepad_t = 1'b0;  // toggles on "STE Joypad Ports"
reg  [1:0] cfg_linkmode = 2'd0;  // link port: 0 off, 1 MIDI, 2 serial (RS-232 at 3.3 V)
reg        cfg_cubase   = 1'b0;  // Cubase 2/3 dongle on the cartridge port

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
		8'h20: cfg_padmode  <= bridge_wr_data[1:0];
		8'h30: cfg_mouse_spd <= bridge_wr_data[1:0];
		8'h34: cfg_stepad_t  <= ~cfg_stepad_t;
		8'h38: cfg_linkmode  <= bridge_wr_data[1:0];
		8'h3C: cfg_cubase    <= bridge_wr_data[0];
		8'h28: cfg_cold_t   <= ~cfg_cold_t;
		8'h2C: begin   // Reset All Settings: defaults, then a cold restart
			cfg_model <= 2'd0; cfg_mem <= 3'd1; cfg_mono <= 1'b0; cfg_blitter <= 1'b0;
			cfg_stereo <= 1'b0; cfg_wp <= 2'b11; cfg_borders <= 1'b1; cfg_padmode <= 2'd1;
			cfg_mouse_spd <= 2'd1; cfg_linkmode <= 2'd0; cfg_cubase <= 1'b0; cfg_cold_t <= ~cfg_cold_t;
		end
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
	8'h20: cfg_bridge_rd_data <= cfg_padmode;
	8'h30: cfg_bridge_rd_data <= cfg_mouse_spd;
	8'h38: cfg_bridge_rd_data <= cfg_linkmode;
	8'h3C: cfg_bridge_rd_data <= cfg_cubase;
	default: cfg_bridge_rd_data <= 0;
	endcase
end

// quasi-static settings, synchronised as a bundle
wire [21:0] cfg_s;
synch_3 #(.WIDTH(22)) s_cfg(
	{cfg_cubase, cfg_linkmode, cfg_stepad_t, cfg_mouse_spd, cfg_cold_t, cfg_reset_t, cfg_model, cfg_mem, cfg_mono, cfg_blitter, cfg_stereo, cfg_wp, cfg_borders, cfg_padmode},
	cfg_s, clk_32);
wire       cubase_32    = cfg_s[21];
wire [1:0] linkmode_32  = cfg_s[20:19];
wire       linkmidi_32  = linkmode_32 == 2'd1;
wire       linkser_32   = linkmode_32 == 2'd2;
wire       stepad_t_32  = cfg_s[18];
wire [1:0] mouse_spd_32 = cfg_s[17:16];
wire       cold_t_32    = cfg_s[15];
wire       reset_t_32   = cfg_s[14];
wire [1:0] model_32     = cfg_s[13:12];
wire [2:0] mem_32       = cfg_s[11:9];
wire       mono_32      = cfg_s[8];
wire       blitter_32   = cfg_s[7];
wire       stereo_32    = cfg_s[6];
wire [1:0] wp_32        = cfg_s[5:4];
wire       borders_32   = cfg_s[3];
wire [1:0] padmode_32   = cfg_s[2:1];

/* ------------------------------------------------------------------------------ */
/* ------------------------------------- Reset ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire reset_n_s;
synch_3 s_rst(reset_n, reset_n_s, clk_32);

wire tos_done;

// "Reset ST" is a warm reset. Machine-shape changes (model, RAM, CPU, monitor) and
// "Cold Restart" go through st_media, which clears low RAM and reloads TOS, so TOS
// sizes memory and detects the hardware again instead of trusting a stale memvalid.
reg  [5:0] machine_d = {2'd0, 3'd1, 1'b0};   // defaults, so power-up is no change
reg        reset_t_d = 1'b0;
reg        cold_t_d  = 1'b0;
reg [15:0] reset_hold = 0;
reg        cold_req = 1'b0;
wire [5:0] machine = {model_32, mem_32, mono_32};

always @(posedge clk_32) begin
	machine_d <= machine;
	reset_t_d <= reset_t_32;
	cold_t_d  <= cold_t_32;
	cold_req  <= (machine != machine_d) || (cold_t_32 != cold_t_d);
	if (reset_hold != 0) reset_hold <= reset_hold - 16'd1;
	if (reset_t_32 != reset_t_d) reset_hold <= 16'hFFFF;
end

wire st_reset = ~reset_n_s | ~tos_done | (reset_hold != 0);

wire [31:0] system_ctrl = {
	1'b0,               // 31
	cubase_32,          // 30 cubase dongle
	1'b0,               // 29 blend
	1'b0,               // 28 viking
	2'b00,              // 27:26 usb redirection
	1'b0,               // 25 ethernec
	model_32[1],        // 24 Mega STE (2) / STEroids (3)
	model_32[0],        // 23 STE (1) / STEroids (3): both bits = MiSTery's 16 MHz turbo STE
	stereo_32,          // 22 PSG stereo
	2'b00,              // 21:20 scanlines
	blitter_32,         // 19 blitter (always on for STE)
	1'b0,               // 18
	acsi_enable,        // 17:10 ACSI devices (one bit per mounted hard disk)
	1'b0,               // 9
	mono_32,            // 8 mono monitor
	wp_32,              // 7:6 floppy write protect
	2'b00,              // 5:4 CPU: 68000 (FX68K) only
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

wire [31:0] hd_size0_74, hd_size1_74, hd_size0, hd_size1;
synch_3 #(.WIDTH(32)) s_hds0(hd_size0_74, hd_size0, clk_32);   // quasi-static
synch_3 #(.WIDTH(32)) s_hds1(hd_size1_74, hd_size1, clk_32);
wire  [7:0] acsi_enable = {6'd0, hd_size1 != 0, hd_size0 != 0};

wire  [1:0] hd_rd, hd_wr;
wire [31:0] hd_lba;
wire        hd_ack;
wire  [7:0] hd_din;
wire  [7:0] dio_status_in;
wire  [3:0] dio_status_index;
wire        dio_ack_t, dio_in_t, dio_out_t;
wire  [7:0] dio_dma_status;
wire [15:0] dio_in_reg, dio_out_reg;
wire [15:0] media_data_in_reg;

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

	.cold_req                   ( cold_req ),
	.tos_done                   ( tos_done ),
	.data_download              ( data_download ),
	.data_addr                  ( data_addr ),
	.data_in_reg                ( media_data_in_reg ),
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
	.sd_din                     ( sd_din ),

	.hd_rd                      ( hd_rd ),
	.hd_wr                      ( hd_wr ),
	.hd_lba                     ( hd_lba ),
	.hd_ack                     ( hd_ack ),
	.hd_din                     ( hd_din ),
	.hd_size0                   ( hd_size0_74 ),
	.hd_size1                   ( hd_size1_74 )
);

/* ------------------------------------------------------------------------------ */
/* ----------------------------- ACSI hard disks -------------------------------- */
/* ------------------------------------------------------------------------------ */
// acsi_ctrl answers the ACSI commands that MiST/MiSTer answer on their ARM.


acsi_ctrl acsi_ctrl (
	.clk          ( clk_32 ),
	.reset        ( st_reset ),
	.status_in    ( dio_status_in ),
	.status_index ( dio_status_index ),
	.dma_ack_t    ( dio_ack_t ),
	.dma_status   ( dio_dma_status ),
	.data_in_t    ( dio_in_t ),
	.data_in_reg  ( dio_in_reg ),
	.data_out_t   ( dio_out_t ),
	.data_out_reg ( dio_out_reg ),
	.blocks0      ( {9'd0, hd_size0[31:9]} ),
	.blocks1      ( {9'd0, hd_size1[31:9]} ),
	.hd_rd        ( hd_rd ),
	.hd_wr        ( hd_wr ),
	.hd_lba       ( hd_lba ),
	.hd_ack       ( hd_ack ),
	.buff_addr    ( sd_buff_addr ),
	.buff_dout    ( sd_dout ),
	.buff_wr      ( sd_dout_strobe & hd_ack ),
	.buff_din     ( hd_din )
);

// data_in_reg is shared by the TOS download and ACSI reads, never at the same time
assign data_in_reg = data_download ? media_data_in_reg : dio_in_reg;

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

// MiST joystick encoding: [0] right [1] left [2] down [3] up [4] fire / A [5] fire 2 / B,
// and for the STE joypad ports (ste_joypad.v) [6] C [7] Option [13] Pause: X, Y and R here.
function [15:0] pad2joy(input [31:0] k);
	pad2joy = {2'd0, k[9], 5'd0, k[7], k[6], k[5], k[4], k[0], k[1], k[2], k[3]};
endfunction

// players 3 and 4 in the Dock, when they are controllers (not the keyboard or mouse),
// are the two extra joysticks of the parallel-port 4-player adapter (Gauntlet II etc.)
wire        pad3_present = cont3_key_s[31:28] != 4'h0 && cont3_key_s[31:28] != 4'h4 && cont3_key_s[31:28] != 4'h5;
wire        pad4_present = cont4_key_s[31:28] != 4'h0 && cont4_key_s[31:28] != 4'h4 && cont4_key_s[31:28] != 4'h5;
wire [15:0] joy2 = pad3_present ? pad2joy(cont3_key_s) : 16'd0;
wire [15:0] joy3 = pad4_present ? pad2joy(cont4_key_s) : 16'd0;

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

// Pad mode: the menu setting is the starting mode; Start cycles mouse -> joystick -> keys.
localparam PM_JOY = 2'd0, PM_MOUSE = 2'd1, PM_KEYS = 2'd2;
reg [1:0] pad_mode = PM_MOUSE;
reg [1:0] padmode_d = PM_MOUSE;
always @(posedge clk_32) begin
	padmode_d <= padmode_32;
	if (padmode_32 != padmode_d) pad_mode <= (padmode_32 == 2'd3) ? PM_MOUSE : padmode_32;
	else if (osk_mouse_toggle)
		pad_mode <= pad_mode == PM_MOUSE ? PM_JOY : pad_mode == PM_JOY ? PM_KEYS : PM_MOUSE;
end
wire pad_mouse_mode = pad_mode == PM_MOUSE && !osk_visible;
wire pad_keys_mode  = pad_mode == PM_KEYS  && !osk_visible;

// show MOUSE / JOYSTICK / KEYS for ~2 s whenever the mode changes
reg [25:0] badge_timer = 26'd0;
reg  [1:0] mode_d = PM_MOUSE;
always @(posedge clk_32) begin
	mode_d <= pad_mode;
	if (pad_mode != mode_d) badge_timer <= 26'd64_000_000;
	else if (badge_timer != 0) badge_timer <= badge_timer - 26'd1;
end

// pad 1 drives the ST joystick port only in joystick mode;
// pad 2 drives the mouse port (port 0), which the IKBD shares with the mouse.
wire [15:0] joy1 = (pad_mode == PM_JOY && !osk_visible) ? pad2joy(cont1_key_s) : 16'd0;
wire [15:0] joy0 = pad2joy(cont2_key_s);

// keys typed by pad 1 (HID usages). Keys mode: every button is a key; otherwise
// X = Space and Y = Return. The on-screen keyboard uses the first four slots.
function [7:0] k(input b, input [7:0] usage); k = b ? usage : 8'h00; endfunction
wire [15:0] p = cont1_key_s[15:0];
// "STE Joypad Ports" presses F11, which MiSTery's IKBD uses to switch the ports (~60 ms)
reg        stepad_d = 1'b0;
reg [20:0] f11_timer = 21'd0;
always @(posedge clk_32) begin
	stepad_d <= stepad_t_32;
	if (stepad_t_32 != stepad_d) f11_timer <= 21'h1FFFFF;
	else if (f11_timer != 0) f11_timer <= f11_timer - 21'd1;
end
wire [7:0] f11_key = f11_timer != 0 ? 8'h44 : 8'h00;

wire [79:0] pad_keys_main = osk_visible ? {osk_key, osk_mods[0] ? 8'hE0 : 8'h00, osk_mods[1] ? 8'hE1 : 8'h00, osk_mods[2] ? 8'hE2 : 8'h00, 48'd0} :
                       pad_keys_mode ? {k(p[0], 8'h52), k(p[1], 8'h51), k(p[2], 8'h50), k(p[3], 8'h4F),   // arrows
                                        k(p[4], 8'h2C), k(p[5], 8'h28), k(p[6], 8'h29), k(p[7], 8'h4B),   // Space Return Esc Help
                                        k(p[8], 8'h3A), k(p[9], 8'h3B)} :                                 // F1 F2
                       {k(p[6], 8'h2C), k(p[7], 8'h28), 64'd0};
wire [87:0] pad_keys = {pad_keys_main, f11_key};

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
// counts per tick for slow / normal / fast; faster once held for ~0.07 s
wire signed [15:0] pad_step =
	mouse_spd_32 == 2'd0 ? (padm_hold[4] ? 16'sd2 : 16'sd1) :
	mouse_spd_32 == 2'd2 ? (padm_hold[4] ? 16'sd6 : 16'sd2) :
	                       (padm_hold[4] ? 16'sd4 : 16'sd1);
always @(posedge clk_32) begin
	pad_mouse_event <= 1'b0;
	padm_tick <= padm_tick + 17'd1;
	if (padm_tick == 0) begin   // ~245 Hz
		if (pad_mouse_mode && pad_dir != 0) begin
			if (padm_hold != 5'd31) padm_hold <= padm_hold + 5'd1;
			pad_dx <= pad_dir[3] ? pad_step : pad_dir[2] ? -pad_step : 16'sd0;
			pad_dy <= pad_dir[1] ? pad_step : pad_dir[0] ? -pad_step : 16'sd0;
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
// [39:32] month [47:40] year (00-99) [55:48] weekday.

// BCD clock, set from the Pocket's RTC at boot and advanced every second
reg [63:0] rtc_74 = 64'd0;
reg [26:0] rtc_div = 27'd0;
function [7:0] bcd_inc(input [7:0] v); bcd_inc = (v[3:0] == 4'd9) ? {v[7:4] + 4'd1, 4'd0} : v + 8'd1; endfunction
function [7:0] month_days(input [7:0] month, input [7:0] year);   // BCD in, BCD out
	case (month)
		8'h04, 8'h06, 8'h09, 8'h11: month_days = 8'h30;
		8'h02: month_days = (({4'd0, year[7:4]} * 8'd10 + {4'd0, year[3:0]}) % 8'd4 == 0) ? 8'h29 : 8'h28;
		default: month_days = 8'h31;
	endcase
endfunction
always @(posedge clk_74a) begin
	rtc_div <= rtc_div + 27'd1;
	if (rtc_valid) begin
		rtc_74 <= {8'h00, 8'h00, rtc_date_bcd[23:16], rtc_date_bcd[15:8], rtc_date_bcd[7:0],
		           rtc_time_bcd[23:16], rtc_time_bcd[15:8], rtc_time_bcd[7:0]};
		rtc_div <= 27'd0;
	end else if (rtc_div == 27'd74_249_999) begin
		rtc_div <= 27'd0;
		if (rtc_74[7:0] != 8'h59) rtc_74[7:0] <= bcd_inc(rtc_74[7:0]);
		else begin
			rtc_74[7:0] <= 8'h00;
			if (rtc_74[15:8] != 8'h59) rtc_74[15:8] <= bcd_inc(rtc_74[15:8]);
			else begin
				rtc_74[15:8] <= 8'h00;
				if (rtc_74[23:16] != 8'h23) rtc_74[23:16] <= bcd_inc(rtc_74[23:16]);
				else begin
					rtc_74[23:16] <= 8'h00;
					if (rtc_74[31:24] != month_days(rtc_74[39:32], rtc_74[47:40])) rtc_74[31:24] <= bcd_inc(rtc_74[31:24]);
					else begin
						rtc_74[31:24] <= 8'h01;
						if (rtc_74[39:32] != 8'h12) rtc_74[39:32] <= bcd_inc(rtc_74[39:32]);
						else begin rtc_74[39:32] <= 8'h01; rtc_74[47:40] <= bcd_inc(rtc_74[47:40]); end
					end
				end
			end
		end
	end
end
wire [63:0] rtc;
synch_3 #(.WIDTH(64)) s_rtc(rtc_74, rtc, clk_32);

/* ------------------------------------------------------------------------------ */
/* --------------------------------- The Atari ST ------------------------------- */
/* ------------------------------------------------------------------------------ */

wire  [3:0] st_r, st_g, st_b;
wire        st_hsync_n, st_vsync_n, st_hblank_n, st_vblank_n, st_blank_n;
wire        st_monomode;
wire [14:0] audio_mix_l, audio_mix_r;

/* ------------------------------------------------------------------------------ */
/* ------------------------------ MIDI on the link port ------------------------- */
/* ------------------------------------------------------------------------------ */
// The ST's MIDI ACIA runs at 31250 baud, the rate Analogue's link-port MIDI cable
// carries. MIDI IN: link SI -> ACIA RX. MIDI OUT: ACIA TX -> link SO.
// Serial: the MFP's real UART (serial_redirect off), baud set by TOS/software.
wire midi_tx, uart_tx;
reg  [2:0] link_si_s = 3'b111;
always @(posedge clk_32) link_si_s <= {link_si_s[1:0], port_tran_si};
wire midi_rx = linkmidi_32 ? link_si_s[2] : 1'b1;
wire uart_rx = linkser_32  ? link_si_s[2] : 1'b1;

// the pad drivers live in the clk_74a-facing top level; keep their inputs registered
reg  link_on_74 = 1'b0, link_tx_74 = 1'b1;
always @(posedge clk_74a) begin
	link_on_74 <= cfg_linkmode == 2'd1 || cfg_linkmode == 2'd2;
	link_tx_74 <= cfg_linkmode == 2'd2 ? uart_tx : midi_tx;
end

atarist_sdram #(1'b0, 1'b1) atarist (   // TG68K (68020) not built: no ST had one
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
	.midi_rx             ( midi_rx ),
	.midi_tx             ( midi_tx ),

	.parallel_in_strobe  ( ~joy3[4] ),
	.parallel_in         ( {~joy2[0], ~joy2[1], ~joy2[2], ~joy2[3], ~joy3[0], ~joy3[1], ~joy3[2], ~joy3[3]} ),
	.parallel_out_strobe ( ),
	.parallel_out        ( ),
	.parallel_printer_busy ( joy2[4] ),

	.serial_redirect     ( ~linkser_32 ),
	.serial_data_out_available ( ),
	.serial_strobe_out   ( 1'b0 ),
	.serial_data_out     ( ),
	.serial_status_out   ( ),
	.serial_strobe_in    ( 1'b0 ),
	.serial_data_in      ( 8'h00 ),
	.uart_ctsb           ( 1'b0 ),
	.uart_rtsb           ( ),
	.uart_rx             ( uart_rx ),
	.uart_tx             ( uart_tx ),

	.data_in_strobe_rom  ( data_in_strobe ),
	.data_in_strobe_acsi ( dio_in_t ),
	.data_in_reg         ( data_in_reg ),
	.data_addr           ( data_addr ),
	.data_download       ( data_download ),

	.data_out_strobe     ( dio_out_t ),
	.data_out_reg        ( dio_out_reg ),
	.dma_ack             ( dio_ack_t ),
	.dma_status          ( dio_dma_status ),
	.dma_nak             ( 1'b0 ),
	.dma_status_in       ( dio_status_in ),
	.dma_status_index    ( dio_status_index ),

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
	.badge      ( badge_timer != 0 ),
	.badge_mode ( pad_mode ),
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
