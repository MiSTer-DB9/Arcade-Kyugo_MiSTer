//  Based on MAME kyugo.cpp (Ernesto Corvi, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module kyugo_board
(
	input         reset,
	input         clk_49m,
	output  [4:0] red, green, blue,
	output        video_hsync, video_vsync, video_csync,
	output        video_hblank, video_vblank,
	output        ce_pix,
	input   [7:0] p1_controls,
	input   [7:0] p2_controls,
	input   [7:0] sys_controls,
	input  [15:0] dip_sw,
    input         rot_flip,
	output signed [15:0] sound,
	input   [3:0] h_center, v_center,
	input   [2:0] variant_sel,
	output  [1:0] coin_counter,
	input         pause,
	input  [15:0] hs_address,
	input   [7:0] hs_data_in,
	output  [7:0] hs_data_out,
	input         hs_write,

	output chip_pool_pkg::z80r_i_t z80_0_i,
	input  chip_pool_pkg::z80r_o_t z80_0_o,
	output chip_pool_pkg::z80r_i_t z80_1_i,
	input  chip_pool_pkg::z80r_o_t z80_1_o,
	output chip_pool_pkg::ay_i_t   ay_0_i,
	input  chip_pool_pkg::ay_o_t   ay_0_o,
	output chip_pool_pkg::ay_i_t   ay_1_i,
	input  chip_pool_pkg::ay_o_t   ay_1_o,

	output [14:0] rom0_a,  input [7:0] rom0_d,
	output [14:0] rom1_a,  input [7:0] rom1_d,
	output [11:0] rom2_a,  input [7:0] rom2_d,
	output [13:0] rom3_a,  input [7:0] rom3_d,
	output [13:0] rom4_a,  input [7:0] rom4_d,
	output [13:0] rom5_a,  input [7:0] rom5_d,
	output [14:0] rom6_a,  input [7:0] rom6_d,
	output [14:0] rom7_a,  input [7:0] rom7_d,
	output [14:0] rom8_a,  input [7:0] rom8_d,
	output  [7:0] rom9_a,  input [7:0] rom9_d,
	output  [7:0] rom10_a, input [7:0] rom10_d,
	output  [7:0] rom11_a, input [7:0] rom11_d,
	output  [4:0] rom12_a, input [7:0] rom12_d,

	output ram_pool_pkg::pram_i_t [7:0] pr_i,
	input  ram_pool_pkg::pram_o_t [7:0] pr_o
);

wire [1:0] pix_cen_o;
jtframe_frac_cen #(2) pix_cen (.clk(clk_49m), .n(10'd4), .m(10'd32), .cen(pix_cen_o), .cenb());
wire cen_pix = pix_cen_o[0];
assign ce_pix = cen_pix;

reg [3:0] cpu_div = 4'd0;
always_ff @(posedge clk_49m) cpu_div <= cpu_div + 4'd1;
wire cen_cpu = (cpu_div == 4'd0);

reg ay_toggle = 1'b0;
always_ff @(posedge clk_49m) if (cen_cpu) ay_toggle <= ~ay_toggle;
wire cen_ay = cen_cpu & ~ay_toggle & ~pause;

reg [8:0] base_h_cnt = 9'd0;
reg [8:0] v_cnt      = 9'd0;

// Forced 0: 180-degree sets rotate through screen_rotate (rot_flip); Gyrodine.mra rot_flip = 0 depends on it.
wire flip_screen = 1'b0;
wire       nmi_mask;
wire [8:0] h_cnt_rot;
wire [8:0] v_cnt_rot;
wire [8:0] h_cnt_sync = base_h_cnt;
wire [8:0] v_cnt_sync = v_cnt;

assign h_cnt_rot = { base_h_cnt[8], base_h_cnt[7:0] ^ {8{flip_screen}} };
assign v_cnt_rot = { v_cnt[8],      v_cnt[7:0]      ^ {8{flip_screen}} };

always_ff @(posedge clk_49m) begin
	if (cen_pix) begin
		if (base_h_cnt == 9'd395) begin
			base_h_cnt <= 9'd0;
			v_cnt <= (v_cnt == 9'd259) ? 9'd0 : v_cnt + 9'd1;
		end else begin
			base_h_cnt <= base_h_cnt + 9'd1;
		end
	end
end

wire hblk = (base_h_cnt >= 9'd288);
wire vblk = (v_cnt < 9'd16) | (v_cnt >= 9'd240);
assign video_hblank = hblk;
assign video_vblank = vblk;

wire [8:0] hs_start = 9'd292 + {5'd0, h_center};
wire [8:0] hs_end   = hs_start + 9'd16;
wire [8:0] vs_start = 9'd242 + {5'd0, v_center};
wire [8:0] vs_end   = vs_start + 9'd4;
assign video_hsync = (h_cnt_sync >= hs_start && h_cnt_sync < hs_end);
assign video_vsync = (v_cnt_sync >= vs_start && v_cnt_sync < vs_end);
assign video_csync = ~(video_hsync ^ video_vsync);

wire       wdog_rst;
// Watchdog reboot masks the unsolved cold-boot SUB CHECK handshake: keep wdog_arm = 1 or Gyrodine won't boot.
wire       wdog_arm = 1'b1;
wire       reset_cpu = reset & ~(wdog_rst & wdog_arm);

wire [15:0] cpu1_A;
wire [7:0]  cpu1_Dout;
wire        cpu1_WR_n, cpu1_RD_n, cpu1_MREQ_n, cpu1_IORQ_n, cpu1_M1_n, cpu1_RFSH_n;

assign cpu1_A    = z80_0_o.a;      assign cpu1_Dout   = z80_0_o.dout;
assign cpu1_M1_n = z80_0_o.m1_n;   assign cpu1_MREQ_n = z80_0_o.mreq_n; assign cpu1_IORQ_n = z80_0_o.iorq_n;
assign cpu1_RD_n = z80_0_o.rd_n;   assign cpu1_WR_n   = z80_0_o.wr_n;   assign cpu1_RFSH_n = z80_0_o.rfsh_n;

// NMI held ~16 cen_cpu ticks: a shorter pulse can fall between CEN samples and be missed.
reg cpu1_nmi = 1'b0;
reg [4:0] nmi_cnt = 5'd0;
always_ff @(posedge clk_49m) begin
	if (!reset_cpu) begin cpu1_nmi <= 1'b0; nmi_cnt <= 5'd0; end
	else if (cen_pix && (base_h_cnt == 9'd0) && (v_cnt == 9'd240) && nmi_mask) begin
		cpu1_nmi <= 1'b1;
		nmi_cnt  <= 5'd16;
	end else if (cen_cpu && (nmi_cnt != 5'd0)) begin
		nmi_cnt <= nmi_cnt - 5'd1;
		if (nmi_cnt == 5'd1) cpu1_nmi <= 1'b0;
	end
end

localparam [2:0] VAR_GYRO     = 3'd0,
                 VAR_REPULSE  = 3'd1,
                 VAR_FLASHGAL = 3'd2,
                 VAR_SRDMISSN = 3'd3,
                 VAR_LEGEND   = 3'd4;

wire cpu1_mem_valid = ~cpu1_MREQ_n & cpu1_RFSH_n;
wire cs_rom       = cpu1_mem_valid & ~cpu1_A[15];
wire cs_bgvram    = cpu1_mem_valid & (cpu1_A[15:11] == 5'b10000);
wire cs_bgattr    = cpu1_mem_valid & (cpu1_A[15:11] == 5'b10001);
wire cs_fgvram    = cpu1_mem_valid & (cpu1_A[15:11] == 5'b10010);
wire cs_spram1    = cpu1_mem_valid & (cpu1_A[15:11] == 5'b10011);
wire cs_spram0    = cpu1_mem_valid & (cpu1_A[15:11] == 5'b10100);
wire cs_scrollxlo = cpu1_mem_valid & ~cpu1_WR_n & (cpu1_A[15:0] == 16'hA800);
wire cs_gfxctrl   = cpu1_mem_valid & ~cpu1_WR_n & (cpu1_A[15:0] == 16'hB000);
wire cs_scrolly   = cpu1_mem_valid & ~cpu1_WR_n & (cpu1_A[15:0] == 16'hB800);
wire cs_e000_blk  = cpu1_mem_valid & (cpu1_A[15:11] == 5'b11100);
wire cs_watchdog  = cs_e000_blk & (variant_sel == VAR_GYRO);
wire cs_shared_e  = cs_e000_blk & (variant_sel == VAR_SRDMISSN);
wire cs_shared    = cpu1_mem_valid & (cpu1_A[15:11] == 5'b11110);
wire cs_mainlatch = ~cpu1_IORQ_n & ~cpu1_WR_n;

reg [7:0] mainlatch = 8'd0;
always_ff @(posedge clk_49m) begin
	if (!reset_cpu) mainlatch <= 8'd0;
	else if (cen_cpu && cs_mainlatch) mainlatch[cpu1_A[2:0]] <= cpu1_Dout[0];
end
reg ml0_seen = 1'b0;
always_ff @(posedge clk_49m) begin
	if (!reset_cpu)        ml0_seen <= 1'b0;
	else if (mainlatch[0]) ml0_seen <= 1'b1;
end
assign nmi_mask = mainlatch[0];

wire cpu2_rst    = ~mainlatch[2];

localparam [8:0] WDOG_TIMEOUT = 9'd120;
reg  [8:0] wdog_frames = 9'd0;
reg  [9:0] wdog_pulse  = 10'd0;
reg        wdog_vblk_d = 1'b0;
assign     wdog_rst    = (wdog_pulse != 10'd0);
always_ff @(posedge clk_49m) begin
	if (!reset) begin
		wdog_frames <= 9'd0; wdog_pulse <= 10'd0; wdog_vblk_d <= 1'b0;
	end else begin
		wdog_vblk_d <= vblk;
		if (wdog_rst) begin
			wdog_pulse  <= wdog_pulse - 10'd1;
			wdog_frames <= 9'd0;
		end else if (cs_watchdog & ~cpu1_WR_n) begin
			wdog_frames <= 9'd0;
		end else if (pause) begin
			wdog_frames <= 9'd0;
		end else if (vblk & ~wdog_vblk_d & (variant_sel == VAR_GYRO)) begin
			if (wdog_frames >= WDOG_TIMEOUT) begin
				wdog_pulse  <= 10'h3FF;
				wdog_frames <= 9'd0;
			end else
				wdog_frames <= wdog_frames + 9'd1;
		end
	end
end

wire [15:0] cpu2_A;
wire [7:0]  cpu2_Dout;
wire        cpu2_WR_n, cpu2_RD_n, cpu2_MREQ_n, cpu2_IORQ_n, cpu2_M1_n, cpu2_RFSH_n;

assign cpu2_A    = z80_1_o.a;      assign cpu2_Dout   = z80_1_o.dout;
assign cpu2_M1_n = z80_1_o.m1_n;   assign cpu2_MREQ_n = z80_1_o.mreq_n; assign cpu2_IORQ_n = z80_1_o.iorq_n;
assign cpu2_RD_n = z80_1_o.rd_n;   assign cpu2_WR_n   = z80_1_o.wr_n;   assign cpu2_RFSH_n = z80_1_o.rfsh_n;

reg cpu2_irq = 1'b0;
always_ff @(posedge clk_49m) begin
	if (!reset_cpu || cpu2_rst) cpu2_irq <= 0;
	else begin
		if (cen_pix && (base_h_cnt == 9'd0) && (v_cnt[5:0] == 6'h20))
			cpu2_irq <= 1;
		if (~cpu2_IORQ_n & ~cpu2_M1_n) cpu2_irq <= 0;
	end
end

wire cpu2_mem_valid = ~cpu2_MREQ_n & cpu2_RFSH_n;

wire cs2_rom = cpu2_mem_valid & ((variant_sel == VAR_GYRO)
                                 ? (~cpu2_A[15] & ~cpu2_A[14] & ~cpu2_A[13])
                                 : ~cpu2_A[15]);

wire cs2_shared = cpu2_mem_valid &
    ( ((variant_sel == VAR_GYRO)     && (cpu2_A[15:11] == 5'b01000))
    | ((variant_sel == VAR_REPULSE)  && (cpu2_A[15:11] == 5'b10100))
    | ((variant_sel == VAR_FLASHGAL) && (cpu2_A[15:11] == 5'b11100))
    | ((variant_sel == VAR_SRDMISSN) && (cpu2_A[15:11] == 5'b10000))
    | ((variant_sel == VAR_LEGEND)   && (cpu2_A[15:11] == 5'b11000)) );

wire cs2_subram = cpu2_mem_valid & (variant_sel == VAR_SRDMISSN) & (cpu2_A[15:11] == 5'b10001);

wire cs2_p1, cs2_p2, cs2_system;
assign cs2_system = cpu2_mem_valid &
    ( ((variant_sel == VAR_GYRO)     && (cpu2_A[15:0] == 16'h8080))
    | ((variant_sel == VAR_REPULSE)  && (cpu2_A[15:0] == 16'hC080))
    | ((variant_sel == VAR_FLASHGAL) && (cpu2_A[15:0] == 16'hC040))
    | ((variant_sel == VAR_SRDMISSN) && (cpu2_A[15:0] == 16'hF400))
    | ((variant_sel == VAR_LEGEND)   && (cpu2_A[15:0] == 16'hF800)) );
assign cs2_p1 = cpu2_mem_valid &
    ( ((variant_sel == VAR_GYRO)     && (cpu2_A[15:0] == 16'h8040))
    | ((variant_sel == VAR_REPULSE)  && (cpu2_A[15:0] == 16'hC040))
    | ((variant_sel == VAR_FLASHGAL) && (cpu2_A[15:0] == 16'hC080))
    | ((variant_sel == VAR_SRDMISSN) && (cpu2_A[15:0] == 16'hF401))
    | ((variant_sel == VAR_LEGEND)   && (cpu2_A[15:0] == 16'hF801)) );
assign cs2_p2 = cpu2_mem_valid &
    ( ((variant_sel == VAR_GYRO)     && (cpu2_A[15:0] == 16'h8000))
    | ((variant_sel == VAR_REPULSE)  && (cpu2_A[15:0] == 16'hC000))
    | ((variant_sel == VAR_FLASHGAL) && (cpu2_A[15:0] == 16'hC0C0))
    | ((variant_sel == VAR_SRDMISSN) && (cpu2_A[15:0] == 16'hF402))
    | ((variant_sel == VAR_LEGEND)   && (cpu2_A[15:0] == 16'hF802)) );

wire io_active = ~cpu2_IORQ_n & cpu2_M1_n;

wire [7:0] ay1_base = (variant_sel == VAR_FLASHGAL) ? 8'h40 :
                      (variant_sel == VAR_SRDMISSN || variant_sel == VAR_LEGEND) ? 8'h80 :
                      8'h00;
wire [7:0] ay2_base = (variant_sel == VAR_GYRO)     ? 8'hC0 :
                      (variant_sel == VAR_REPULSE)  ? 8'h40 :
                      (variant_sel == VAR_FLASHGAL) ? 8'h80 :
                                                      8'h84;
wire [7:0] coin_base = (variant_sel == VAR_REPULSE || variant_sel == VAR_FLASHGAL) ? 8'hC0 :
                       (variant_sel == VAR_SRDMISSN || variant_sel == VAR_LEGEND)  ? 8'h90 :
                                                                                     8'hFF;

wire cs2_ay1_addr = io_active & ~cpu2_WR_n & (cpu2_A[7:0] == ay1_base);
wire cs2_ay1_data = io_active & ~cpu2_WR_n & (cpu2_A[7:0] == (ay1_base | 8'h01));
wire cs2_ay1_rd   = io_active & ~cpu2_RD_n & (cpu2_A[7:0] == (ay1_base | 8'h02));
wire cs2_ay2_addr = io_active & ~cpu2_WR_n & (cpu2_A[7:0] == ay2_base);
wire cs2_ay2_data = io_active & ~cpu2_WR_n & (cpu2_A[7:0] == (ay2_base | 8'h01));
wire cs2_coin_w   = io_active & ~cpu2_WR_n & (variant_sel != VAR_GYRO) &
                    ((cpu2_A[7:0] == coin_base) | (cpu2_A[7:0] == (coin_base | 8'h01)));

reg [1:0] coin_counter_r = 2'd0;
always_ff @(posedge clk_49m) begin
    if (!reset) coin_counter_r <= 2'd0;
    else if (cen_cpu && cs2_coin_w) coin_counter_r[cpu2_A[0]] <= cpu2_Dout[0];
end
assign coin_counter = coin_counter_r;

wire [7:0] main_rom_D = rom0_d;
assign rom0_a = cpu1_A[14:0];

wire [7:0] sub_rom_D;
assign rom1_a = cpu2_A[14:0];
assign sub_rom_D = rom1_d;

wire [7:0] bgvram_D, bgvram_rD;
reg [10:0] bgvram_raddr;
assign pr_i[1].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[1].a_d = cpu1_Dout; assign pr_i[1].a_we = cs_bgvram & ~cpu1_WR_n;
assign pr_i[1].b_addr = {5'd0, bgvram_raddr}; assign pr_i[1].b_d = 8'd0; assign pr_i[1].b_we = 1'b0;
assign bgvram_D = pr_o[1].a_q; assign bgvram_rD = pr_o[1].b_q;

wire [7:0] bgattr_D, bgattr_rD;
reg [10:0] bgattr_raddr;
assign pr_i[2].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[2].a_d = cpu1_Dout; assign pr_i[2].a_we = cs_bgattr & ~cpu1_WR_n;
assign pr_i[2].b_addr = {5'd0, bgattr_raddr}; assign pr_i[2].b_d = 8'd0; assign pr_i[2].b_we = 1'b0;
assign bgattr_D = pr_o[2].a_q; assign bgattr_rD = pr_o[2].b_q;

wire [7:0] fgvram_D, fgvram_rD;
reg [10:0] fgvram_raddr;
assign pr_i[3].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[3].a_d = cpu1_Dout; assign pr_i[3].a_we = cs_fgvram & ~cpu1_WR_n;
assign pr_i[3].b_addr = {5'd0, fgvram_raddr}; assign pr_i[3].b_d = 8'd0; assign pr_i[3].b_we = 1'b0;
assign fgvram_D = pr_o[3].a_q; assign fgvram_rD = pr_o[3].b_q;

wire [7:0] spram1_D, spram1_rD;
reg [10:0] spram1_raddr;
assign pr_i[6].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[6].a_d = cpu1_Dout; assign pr_i[6].a_we = cs_spram1 & ~cpu1_WR_n;
assign pr_i[6].b_addr = {5'd0, spram1_raddr}; assign pr_i[6].b_d = 8'd0; assign pr_i[6].b_we = 1'b0;
assign spram1_D = pr_o[6].a_q; assign spram1_rD = pr_o[6].b_q;

wire [7:0] spram0_D, spram0_rD;
reg [10:0] spram0_raddr;
assign pr_i[5].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[5].a_d = cpu1_Dout; assign pr_i[5].a_we = cs_spram0 & ~cpu1_WR_n;
assign pr_i[5].b_addr = {5'd0, spram0_raddr}; assign pr_i[5].b_d = 8'd0; assign pr_i[5].b_we = 1'b0;
assign spram0_D = pr_o[5].a_q; assign spram0_rD = pr_o[5].b_q;

wire [7:0] shared_ram_D_cpu1, shared_ram_D_cpu2;
wire       cs_shared_main = cs_shared | cs_shared_e;
assign pr_i[0].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[0].a_d = cpu1_Dout; assign pr_i[0].a_we = cs_shared_main & ~cpu1_WR_n;
assign pr_i[0].b_addr = {5'd0, cpu2_A[10:0]}; assign pr_i[0].b_d = cpu2_Dout; assign pr_i[0].b_we = cs2_shared & ~cpu2_WR_n;
assign shared_ram_D_cpu1 = pr_o[0].a_q; assign shared_ram_D_cpu2 = pr_o[0].b_q;

assign hs_data_out = shared_ram_D_cpu1;

wire [7:0] subram_D;
assign pr_i[7].a_addr = {5'd0, cpu2_A[10:0]}; assign pr_i[7].a_d = cpu2_Dout; assign pr_i[7].a_we = cs2_subram & ~cpu2_WR_n;
assign pr_i[7].b_addr = 16'd0; assign pr_i[7].b_d = 8'd0; assign pr_i[7].b_we = 1'b0;
assign subram_D = pr_o[7].a_q;

wire [7:0] cpu1_Din = cs_rom         ? main_rom_D             :
                      cs_bgvram      ? bgvram_D                :
                      cs_bgattr      ? bgattr_D                :
                      cs_fgvram      ? fgvram_D                :
                      cs_spram1      ? (spram1_D | 8'hF0)     :
                      cs_spram0      ? spram0_D                :
                      cs_shared_main ? shared_ram_D_cpu1       : 8'hFF;

wire [7:0] p1_inputs     = p1_controls;
wire [7:0] p2_inputs     = p2_controls;
wire [7:0] system_inputs = sys_controls;

reg [7:0] scroll_x_lo = 8'd0;
reg       scroll_x_hi = 1'b0;
reg [7:0] scroll_y_r  = 8'd0;
reg       fgcolor     = 1'b0;
reg       bgpalbank   = 1'b0;

always_ff @(posedge clk_49m) begin
	if (!reset) begin
		scroll_x_lo <= 8'd0; scroll_x_hi <= 1'b0;
		scroll_y_r  <= 8'd0; fgcolor     <= 1'b0; bgpalbank <= 1'b0;
	end else if (cen_cpu) begin
		if (cs_scrollxlo) scroll_x_lo <= cpu1_Dout;
		if (cs_scrolly)   scroll_y_r  <= cpu1_Dout;
		if (cs_gfxctrl) begin
			scroll_x_hi <= cpu1_Dout[0];
			fgcolor     <= cpu1_Dout[5];
			bgpalbank   <= cpu1_Dout[6];
		end
	end
end

wire [7:0] ay1_dout;
wire [9:0] ay1_sound;
assign ay_0_i.ce = cen_ay; assign ay_0_i.bdir = cs2_ay1_addr | cs2_ay1_data; assign ay_0_i.bc1 = cs2_ay1_addr | cs2_ay1_rd;
assign ay_0_i.din = cpu2_Dout; assign ay_0_i.ioa_in = dip_sw[7:0]; assign ay_0_i.iob_in = dip_sw[15:8];
assign ay1_dout = ay_0_o.dout; assign ay1_sound = ay_0_o.sound;

wire [7:0] ay2_dout;
wire [9:0] ay2_sound;
assign ay_1_i.ce = cen_ay; assign ay_1_i.bdir = cs2_ay2_addr | cs2_ay2_data; assign ay_1_i.bc1 = cs2_ay2_addr;
assign ay_1_i.din = cpu2_Dout; assign ay_1_i.ioa_in = 8'hFF; assign ay_1_i.iob_in = 8'hFF;
assign ay2_dout = ay_1_o.dout; assign ay2_sound = ay_1_o.sound;

assign sound = $signed({1'b0, ay1_sound, 4'd0}) + $signed({1'b0, ay2_sound, 4'd0});

wire [7:0] cpu2_Din = (~cpu2_IORQ_n) ? (cs2_ay1_rd ? ay1_dout : 8'hFF) :
                      cs2_rom    ? sub_rom_D         :
                      cs2_shared ? shared_ram_D_cpu2 :
                      cs2_subram ? subram_D          :
                      cs2_p2     ? p2_inputs         :
                      cs2_p1     ? p1_inputs         :
                      cs2_system ? system_inputs     : 8'hFF;

reg [11:0] fgtile_addr;
wire [7:0] fgtile_D;
assign rom2_a = fgtile_addr;
assign fgtile_D = rom2_d;

reg [13:0] bg0_addr, bg1_addr, bg2_addr;
wire [7:0] bg0_D, bg1_D, bg2_D;
assign rom3_a = bg0_addr; assign rom4_a = bg1_addr; assign rom5_a = bg2_addr;
assign bg0_D = rom3_d; assign bg1_D = rom4_d; assign bg2_D = rom5_d;

reg [14:0] spr_addr;
wire [7:0] spr0_D, spr1_D, spr2_D;
assign rom6_a = spr_addr; assign rom7_a = spr_addr; assign rom8_a = spr_addr;
assign spr0_D = rom6_d; assign spr1_D = rom7_d; assign spr2_D = rom8_d;

wire [7:0] prom_addr;
reg  [4:0] prom_lut_addr;
wire [7:0] prom_r_D, prom_g_D, prom_b_D;
assign rom9_a = prom_addr; assign rom10_a = prom_addr; assign rom11_a = prom_addr;
assign prom_r_D = rom9_d; assign prom_g_D = rom10_d; assign prom_b_D = rom11_d;

wire [7:0] prom_lut_D = rom12_d;
assign rom12_a = prom_lut_addr;

wire [8:0] bg_sx = flip_screen ? (9'd287 - base_h_cnt) : base_h_cnt;
// Y mirror is 255 - v (visible lines 16..239), not 239 - v.
wire [8:0] bg_sy = flip_screen ? (9'd255 - v_cnt)      : v_cnt;

wire [8:0] scroll_x_full = {scroll_x_hi, scroll_x_lo};

wire flip_req = mainlatch[1];
wire [9:0] bg_world_x_pre = flip_req ? ({1'b0, bg_sx} - {1'b0, scroll_x_full} + 10'd192)
                                     : ({1'b0, bg_sx} + {1'b0, scroll_x_full} + 10'd32);
wire [8:0] bg_world_x = bg_world_x_pre[8:0];
wire [8:0] bg_world_y = bg_sy + {1'b0, scroll_y_r};

wire [5:0] bg_col = bg_world_x[8:3];
wire [4:0] bg_row = bg_world_y[7:3];
wire [2:0] bg_fx  = bg_world_x[2:0];
wire [2:0] bg_fy  = bg_world_y[2:0];

wire bg_row_lookahead = (base_h_cnt >= 9'd384);

wire [8:0] v_cnt_next      = (v_cnt == 9'd259) ? 9'd0 : (v_cnt + 9'd1);
// Same mirror constant as bg_sy (255).
wire [8:0] bg_sy_next      = flip_screen ? (9'd255 - v_cnt_next) : v_cnt_next;
wire [8:0] bg_world_y_next = bg_sy_next + {1'b0, scroll_y_r};
wire [4:0] bg_row_next     = bg_world_y_next[7:3];

wire [8:0] bg_sx_zero           = flip_screen ? 9'd287 : 9'd0;
// Must match bg_world_x_pre's scroll sign exactly, or column 0 disagrees with the rest of the line.
wire [9:0] bg_world_x_zero_pre  = flip_req ? ({1'b0, bg_sx_zero} - {1'b0, scroll_x_full} + 10'd192)
                                           : ({1'b0, bg_sx_zero} + {1'b0, scroll_x_full} + 10'd32);
wire [8:0] bg_world_x_zero      = bg_world_x_zero_pre[8:0];
wire [5:0] bg_col_zero          = bg_world_x_zero[8:3];

wire [4:0] bg_fetch_row = bg_row_lookahead ? bg_row_next : bg_row;
wire [5:0] bg_fetch_col = bg_row_lookahead ? bg_col_zero : (bg_col + 6'd1);

// Fine Y must follow the lookahead row override, or the lookahead tile gets the wrong scanline.
wire [2:0] bg_fetch_fy = bg_row_lookahead ? bg_world_y_next[2:0] : bg_fy;

reg  [9:0] bg_code_nxt;
reg  [4:0] bg_color_nxt;
reg        bg_fx_invert_nxt;
reg  [2:0] bg_fy_eff;
reg  [7:0] bg_p0_nxt, bg_p1_nxt, bg_p2_nxt;

reg  [4:0] bg_color_lat;
reg        bg_fx_invert_lat;
reg  [7:0] bg_p0_lat, bg_p1_lat, bg_p2_lat;

always_ff @(posedge clk_49m) begin
    if (cen_pix) begin
        if (bg_row_lookahead) begin
            case (base_h_cnt)
                9'd384: begin
                    bgvram_raddr <= {bg_fetch_row, bg_fetch_col};
                    bgattr_raddr <= {bg_fetch_row, bg_fetch_col};
                end
                9'd385: begin
                    bg_code_nxt      <= {bgattr_rD[1:0], bgvram_rD};
                    bg_color_nxt     <= {bgpalbank, bgattr_rD[7:4]};
                    // No flip_screen XOR here: the screen-coordinate mirror already flips tile and pixel order.
                    bg_fx_invert_nxt <= bgattr_rD[2];
                    bg_fy_eff        <= bg_fetch_fy ^ {3{bgattr_rD[3]}};
                    bg0_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                    bg1_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                    bg2_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                end
                9'd386: begin
                    bg_p0_nxt <= bg0_D;
                    bg_p1_nxt <= bg1_D;
                    bg_p2_nxt <= bg2_D;
                end
                // Promote fetch 1 (col_zero) before fetch 2 overwrites _nxt.
                9'd387: begin
                    bg_color_lat     <= bg_color_nxt;
                    bg_fx_invert_lat <= bg_fx_invert_nxt;
                    bg_p0_lat        <= bg_p0_nxt;
                    bg_p1_lat        <= bg_p1_nxt;
                    bg_p2_lat        <= bg_p2_nxt;
                end
                9'd388: begin
                    bgvram_raddr <= {bg_fetch_row, (bg_col_zero + 6'd1)};
                    bgattr_raddr <= {bg_fetch_row, (bg_col_zero + 6'd1)};
                end
                9'd389: begin
                    bg_code_nxt      <= {bgattr_rD[1:0], bgvram_rD};
                    bg_color_nxt     <= {bgpalbank, bgattr_rD[7:4]};
                    bg_fx_invert_nxt <= bgattr_rD[2];
                    bg_fy_eff        <= bg_fetch_fy ^ {3{bgattr_rD[3]}};
                    bg0_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                    bg1_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                    bg2_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                end
                9'd390: begin
                    bg_p0_nxt <= bg0_D;
                    bg_p1_nxt <= bg1_D;
                    bg_p2_nxt <= bg2_D;
                end
                // 391-395: no promote here, _lat / _nxt must survive to base_h_cnt == 0.
                default: ;
            endcase
        end else begin
            case (bg_fx)
                3'd0: begin
                    bgvram_raddr <= {bg_fetch_row, bg_fetch_col};
                    bgattr_raddr <= {bg_fetch_row, bg_fetch_col};
                end
                3'd1: begin
                    bg_code_nxt      <= {bgattr_rD[1:0], bgvram_rD};
                    bg_color_nxt     <= {bgpalbank, bgattr_rD[7:4]};
                    bg_fx_invert_nxt <= bgattr_rD[2];
                    bg_fy_eff        <= bg_fetch_fy ^ {3{bgattr_rD[3]}};
                    bg0_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                    bg1_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                    bg2_addr <= {1'b0, {bgattr_rD[1:0], bgvram_rD}, (bg_fetch_fy ^ {3{bgattr_rD[3]}})};
                end
                3'd2: begin
                    bg_p0_nxt <= bg0_D;
                    bg_p1_nxt <= bg1_D;
                    bg_p2_nxt <= bg2_D;
                end
                3'd7: begin
                    bg_color_lat     <= bg_color_nxt;
                    bg_fx_invert_lat <= bg_fx_invert_nxt;
                    bg_p0_lat        <= bg_p0_nxt;
                    bg_p1_lat        <= bg_p1_nxt;
                    bg_p2_lat        <= bg_p2_nxt;
                end
                default: ;
            endcase
        end
    end
end

wire [2:0] bg_pix_bit_idx = bg_fx_invert_lat ? bg_fx : ~bg_fx;
wire bg_p0_bit = bg_p0_lat[bg_pix_bit_idx];
wire bg_p1_bit = bg_p1_lat[bg_pix_bit_idx];
wire bg_p2_bit = bg_p2_lat[bg_pix_bit_idx];
wire [2:0] bg_pix = {bg_p0_bit, bg_p1_bit, bg_p2_bit};

wire [7:0] bg_palette_index = {bg_color_lat[4:0], bg_pix[2:0]};

wire [5:0] fg_col = bg_sx[8:3];
wire [4:0] fg_row = bg_sy[7:3];
wire [2:0] fg_fx  = bg_sx[2:0];
wire [2:0] fg_fy  = bg_sy[2:0];

wire [4:0] fg_row_next = bg_sy_next[7:3];
wire [5:0] fg_col_zero = bg_sx_zero[8:3];

wire [4:0] fg_fetch_row = bg_row_lookahead ? fg_row_next : fg_row;
wire [5:0] fg_fetch_col = bg_row_lookahead ? fg_col_zero : (fg_col + 6'd1);

// Fine Y must follow the lookahead row override, or the lookahead tile gets the wrong scanline.
wire [2:0] fg_fetch_fy = bg_row_lookahead ? bg_sy_next[2:0] : fg_fy;

reg  [7:0] fg_code_nxt;
reg  [5:0] fg_color_nxt;
reg  [7:0] fg_byte_l_nxt, fg_byte_r_nxt;

reg  [5:0] fg_color_lat;
reg  [7:0] fg_byte_l_lat, fg_byte_r_lat;

always_ff @(posedge clk_49m) begin
    if (cen_pix) begin
        if (bg_row_lookahead) begin
            case (base_h_cnt)
                9'd389: fgvram_raddr <= {fg_fetch_row, fg_fetch_col};
                9'd390: begin
                    fg_code_nxt   <= fgvram_rD;
                    prom_lut_addr <= fgvram_rD[7:3];
                end
                9'd391: begin
                    fg_color_nxt <= {prom_lut_D[4:0], fgcolor};
                    fgtile_addr  <= {fg_code_nxt, 1'b0, fg_fetch_fy};
                end
                9'd392: begin
                    fg_byte_l_nxt <= fgtile_D;
                    fgtile_addr   <= {fg_code_nxt, 1'b1, fg_fetch_fy};
                end
                9'd393: fg_byte_r_nxt <= fgtile_D;
                9'd395: begin
                    fg_color_lat  <= fg_color_nxt;
                    fg_byte_l_lat <= fg_byte_l_nxt;
                    fg_byte_r_lat <= fg_byte_r_nxt;
                end
                default: ;
            endcase
        end else begin
            case (fg_fx)
                3'd0: fgvram_raddr <= {fg_fetch_row, fg_fetch_col};
                3'd1: begin
                    fg_code_nxt   <= fgvram_rD;
                    prom_lut_addr <= fgvram_rD[7:3];
                end
                3'd2: begin
                    fg_color_nxt <= {prom_lut_D[4:0], fgcolor};
                    fgtile_addr  <= {fg_code_nxt, 1'b0, fg_fetch_fy};
                end
                3'd3: begin
                    fg_byte_l_nxt <= fgtile_D;
                    fgtile_addr   <= {fg_code_nxt, 1'b1, fg_fetch_fy};
                end
                3'd4: fg_byte_r_nxt <= fgtile_D;
                3'd7: begin
                    fg_color_lat  <= fg_color_nxt;
                    fg_byte_l_lat <= fg_byte_l_nxt;
                    fg_byte_r_lat <= fg_byte_r_nxt;
                end
                default: ;
            endcase
        end
    end
end

wire [7:0] fg_byte_sel = fg_fx[2] ? fg_byte_r_lat : fg_byte_l_lat;
wire [1:0] fg_xic      = ~fg_fx[1:0];
wire fg_p0_bit = fg_byte_sel[{1'b1, fg_xic}];
wire fg_p1_bit = fg_byte_sel[{1'b0, fg_xic}];
wire [1:0] fg_pix = {fg_p0_bit, fg_p1_bit};

wire [7:0] fg_palette_index = {fg_color_lat[5:0], fg_pix[1:0]};

wire [7:0]  fgvram_spr_rD;
reg  [10:0] fgvram_spr_raddr;
assign pr_i[4].a_addr = {5'd0, cpu1_A[10:0]}; assign pr_i[4].a_d = cpu1_Dout; assign pr_i[4].a_we = cs_fgvram & ~cpu1_WR_n;
assign pr_i[4].b_addr = {5'd0, fgvram_spr_raddr}; assign pr_i[4].b_d = 8'd0; assign pr_i[4].b_we = 1'b0;
assign fgvram_spr_rD = pr_o[4].b_q;

reg [8:0] spr_lb_a [0:511];   // POOL-EXCEPTION: 9-bit sprite line buffer (valid + pen); pool blocks are 8 bit
reg [8:0] spr_lb_b [0:511];   // POOL-EXCEPTION: 9-bit sprite line buffer (valid + pen); pool blocks are 8 bit
reg       write_buf;
reg       eol_d;
always_ff @(posedge clk_49m) begin
    if (cen_pix) begin
        eol_d <= (base_h_cnt == 9'd395);
        if (eol_d) write_buf <= ~write_buf;
    end
end

reg       lb_we;
reg [8:0] lb_waddr;
reg [8:0] lb_wdata;
reg [8:0] spr_lb_a_rdata, spr_lb_b_rdata;
always_ff @(posedge clk_49m) begin
    spr_lb_a_rdata <= spr_lb_a[base_h_cnt];
    spr_lb_b_rdata <= spr_lb_b[base_h_cnt];
    if (lb_we && !write_buf) spr_lb_a[lb_waddr] <= lb_wdata;
    if (lb_we &&  write_buf) spr_lb_b[lb_waddr] <= lb_wdata;
end
wire [8:0] spr_lb_rdata = write_buf ? spr_lb_a_rdata : spr_lb_b_rdata;

// *W states: dpram_dc / eprom q is unregistered, data for an address set in state N is valid in state N+2.
localparam [4:0] SS_IDLE = 5'd0,  SS_CLR  = 5'd1,  SS_FS0  = 5'd2,  SS_FS1  = 5'd3,
                 SS_FS2  = 5'd4,  SS_FR0  = 5'd5,  SS_FR1  = 5'd6,  SS_FRL  = 5'd7,
                 SS_FRR  = 5'd8,  SS_WPX  = 5'd9,  SS_NEXT = 5'd10,
                 SS_FS0W = 5'd11, SS_FS1W = 5'd12, SS_FR0W = 5'd13, SS_FR1W = 5'd14,
                 SS_FRLW = 5'd15;

reg [4:0] spr_st;
reg [4:0] slot_n;
reg [8:0] clr_idx;
reg [3:0] px_idx;
reg [8:0] base_h_prev;

reg [7:0] sy_y_raw;
reg [7:0] x_lo_lat;
reg       x_hi_lat;
reg [4:0] color_lat;
reg [8:0] sy_full;
reg signed [10:0] sx_full;
reg [3:0] y_in_tile;
reg [9:0] code_lat;
reg       flipx_lat, flipy_lat;
reg [7:0] p0_l, p1_l, p2_l;
reg [7:0] p0_r, p1_r, p2_r;

wire        slot_div  = (slot_n >= 5'd12);
wire [3:0]  slot_mod  = slot_div ? (slot_n[3:0] - 4'd12) : slot_n[3:0];
wire [10:0] slot_offs = 11'h28 + {6'd0, slot_mod, 1'b0} + (slot_div ? 11'd64 : 11'd0);

wire [8:0] eval_y9   = v_cnt - 9'd15;
wire [7:0] eval_y    = eval_y9[7:0];

wire [8:0] sy_pre  = 9'd257 - {1'b0, sy_y_raw};
wire [8:0] sy_calc = (sy_pre > 9'd240) ? (sy_pre - 9'd256) : sy_pre;
wire [8:0] sx_pre  = {x_hi_lat, x_lo_lat};
// 11-bit signed on purpose: 256..320 must stay positive, only 321..511 wrap negative.
wire signed [10:0] sx_calc = (sx_pre > 9'd320) ? ($signed({2'd0, sx_pre}) - 11'sd512)
                                                : $signed({2'd0, sx_pre});

// 9 bits on purpose: a diff of 256..270 must wrap negative (miss); 10 bits would fake a hit on cell 16.
wire [8:0] hit_diff_norm = {1'b0, eval_y} - sy_full;
wire [8:0] hit_diff_flip = (sy_full + 9'd15) - {1'b0, eval_y};
wire [8:0] hit_diff = flip_screen ? hit_diff_flip : hit_diff_norm;
wire       hit      = (hit_diff[8] == 1'b0);
wire [3:0] hit_row  = hit_diff[7:4];
wire [3:0] hit_yint = flip_screen ? (4'd15 - hit_diff[3:0]) : hit_diff[3:0];

wire [9:0] code_now  = {spram1_rD[0], spram1_rD[1], fgvram_spr_rD};
wire       flipx_now = spram1_rD[3] ^ flip_req;
wire       flipy_now = spram1_rD[2];
wire [3:0] y_eff_now = flipy_now ? (4'd15 - y_in_tile) : y_in_tile;
wire [3:0] y_eff_lat = flipy_lat ? (4'd15 - y_in_tile) : y_in_tile;

wire [3:0] tile_x_eff = flipx_lat ? (4'd15 - px_idx) : px_idx;
wire [7:0] byte0      = tile_x_eff[3] ? p0_r : p0_l;
wire [7:0] byte1      = tile_x_eff[3] ? p1_r : p1_l;
wire [7:0] byte2      = tile_x_eff[3] ? p2_r : p2_l;
wire [2:0] bit_idx    = ~tile_x_eff[2:0];
wire       pix_p0     = byte0[bit_idx];
wire       pix_p1     = byte1[bit_idx];
wire       pix_p2     = byte2[bit_idx];
wire [2:0] spr_pix    = {pix_p0, pix_p1, pix_p2};
wire [7:0] spr_pal_idx = {color_lat[4:0], spr_pix[2:0]};

wire signed [10:0] sx_signed    = sx_full;
wire signed [10:0] screen_x_raw = sx_signed + $signed({7'd0, px_idx});
wire signed [10:0] screen_x_signed = flip_req ? (11'sd287 - screen_x_raw) : screen_x_raw;
wire               screen_x_in_range = (screen_x_signed >= 11'sd0) && (screen_x_signed < 11'sd288);

always_ff @(posedge clk_49m) begin
    if (!reset) begin
        spr_st      <= SS_IDLE;
        slot_n      <= 5'd0;
        clr_idx     <= 9'd0;
        lb_we       <= 1'b0;
        base_h_prev <= 9'd0;
    end else begin
        lb_we <= 1'b0;
        if (cen_pix) base_h_prev <= base_h_cnt;

        if (cen_pix && (base_h_cnt == 9'd0) && (base_h_prev != 9'd0)) begin
            spr_st  <= SS_CLR;
            slot_n  <= 5'd0;
            clr_idx <= 9'd0;
        end else begin
            case (spr_st)
                SS_IDLE: ;
                SS_CLR: begin
                    lb_we    <= 1'b1;
                    lb_waddr <= clr_idx;
                    lb_wdata <= 9'd0;
                    if (clr_idx == 9'd287) begin
                        clr_idx <= 9'd0;
                        spr_st  <= SS_FS0;
                    end else begin
                        clr_idx <= clr_idx + 9'd1;
                    end
                end
                SS_FS0: begin
                    spram0_raddr     <= slot_offs;
                    fgvram_spr_raddr <= slot_offs + 11'd1;
                    spram1_raddr     <= slot_offs + 11'd1;
                    spr_st <= SS_FS0W;
                end
                SS_FS0W: spr_st <= SS_FS1;
                SS_FS1: begin
                    sy_y_raw     <= spram0_rD;
                    x_lo_lat     <= fgvram_spr_rD;
                    x_hi_lat     <= spram1_rD[0];
                    spram0_raddr <= slot_offs + 11'd1;
                    spr_st       <= SS_FS1W;
                end
                SS_FS1W: spr_st <= SS_FS2;
                SS_FS2: begin
                    color_lat <= spram0_rD[4:0];
                    // flip_req offset -16 is measured against a reference frame; the algebra gives -17, keep -16.
                    sy_full   <= flip_screen ? (9'd240 - sy_calc)
                                             : (flip_req ? (sy_calc - 9'd16) : sy_calc);
                    sx_full   <= sx_calc;
                    spr_st    <= SS_FR0;
                end
                SS_FR0: begin
                    if (hit) begin
                        y_in_tile        <= hit_yint;
                        fgvram_spr_raddr <= slot_offs + {hit_row, 7'd0};
                        spram1_raddr     <= slot_offs + {hit_row, 7'd0};
                        spr_st           <= SS_FR0W;
                    end else begin
                        spr_st <= SS_NEXT;
                    end
                end
                SS_FR0W: spr_st <= SS_FR1;
                SS_FR1: begin
                    code_lat  <= code_now;
                    flipx_lat <= flipx_now;
                    flipy_lat <= flipy_now;
                    spr_addr  <= {code_now[9:0], y_eff_now[3], 1'b0, y_eff_now[2:0]};
                    spr_st    <= SS_FR1W;
                end
                SS_FR1W: spr_st <= SS_FRL;
                SS_FRL: begin
                    p0_l <= spr0_D;
                    p1_l <= spr1_D;
                    p2_l <= spr2_D;
                    spr_addr <= {code_lat[9:0], y_eff_lat[3], 1'b1, y_eff_lat[2:0]};
                    spr_st <= SS_FRLW;
                end
                SS_FRLW: spr_st <= SS_FRR;
                SS_FRR: begin
                    p0_r   <= spr0_D;
                    p1_r   <= spr1_D;
                    p2_r   <= spr2_D;
                    px_idx <= 4'd0;
                    spr_st <= SS_WPX;
                end
                SS_WPX: begin
                    if (screen_x_in_range && (spr_pix != 3'b000)) begin
                        lb_we    <= 1'b1;
                        lb_waddr <= screen_x_signed[8:0];
                        lb_wdata <= {1'b1, spr_pal_idx};
                    end
                    if (px_idx == 4'd15) begin
                        spr_st <= SS_NEXT;
                    end else begin
                        px_idx <= px_idx + 4'd1;
                    end
                end
                SS_NEXT: begin
                    if (slot_n == 5'd23) begin
                        spr_st <= SS_IDLE;
                    end else begin
                        slot_n <= slot_n + 5'd1;
                        spr_st <= SS_FS0;
                    end
                end
                default: spr_st <= SS_IDLE;
            endcase
        end
    end
end

wire       spr_opaque         = spr_lb_rdata[8];
wire [7:0] spr_palette_index  = spr_lb_rdata[7:0];
wire       fg_opaque          = (fg_pix != 2'b00);

wire [7:0] composite_pal = fg_opaque  ? fg_palette_index  :
                           spr_opaque ? spr_palette_index :
                                        bg_palette_index;
wire visible = ~hblk & ~vblk;

assign prom_addr = composite_pal;
assign red   = !visible ? 5'd0 : {prom_r_D[3:0], prom_r_D[3]};
assign green = !visible ? 5'd0 : {prom_g_D[3:0], prom_g_D[3]};
assign blue  = !visible ? 5'd0 : {prom_b_D[3:0], prom_b_D[3]};

assign z80_0_i.reset_n = reset_cpu; assign z80_0_i.ce = cen_cpu & ~pause; assign z80_0_i.int_n = 1'b1; assign z80_0_i.nmi_n = ~cpu1_nmi;
assign z80_0_i.di = cpu1_Din;
// Both Z80s must keep identical reset / CE timing: the boot handshake depends on their relative speed.
assign z80_1_i.reset_n = reset_cpu & ~cpu2_rst; assign z80_1_i.ce = cen_cpu & ~pause; assign z80_1_i.int_n = ~cpu2_irq; assign z80_1_i.nmi_n = 1'b1;
assign z80_1_i.di = cpu2_Din;

endmodule
