//  Copyright (C) 2026 Rodimus
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.

module kyugo_dispatcher
(
	input                reset,
	input                clk_49m,

	input          [7:0] p1_controls,
	input          [7:0] p2_controls,
	input          [7:0] sys_controls,

	input         [15:0] dip_sw,

    input                rot_flip,

	output               video_hsync, video_vsync, video_csync,
	output               video_hblank, video_vblank,
	output               ce_pix,
	output         [4:0] video_r, video_g, video_b,

	output signed [15:0] sound,

	input          [3:0] h_center, v_center,

	input         [24:0] ioctl_addr,
	input          [7:0] ioctl_data,
	input                ioctl_wr,
	input          [7:0] ioctl_index,

	input                pause,

	input         [15:0] hs_address,
	input          [7:0] hs_data_in,
	output         [7:0] hs_data_out,
	input                hs_write
);

wire main_rom_cs_i, sub_rom_cs_i, fg_rom_cs_i;
wire bg0_rom_cs_i, bg1_rom_cs_i, bg2_rom_cs_i;
wire spr0_rom_cs_i, spr1_rom_cs_i, spr2_rom_cs_i;
wire prom_r_cs_i, prom_g_cs_i, prom_b_cs_i;
wire prom_lut_cs_i, prom_tim_cs_i;

wire ioctl_wr_cpu = ioctl_wr && (ioctl_index == 8'd0);

reg [2:0] variant_sel = 3'd0;
always_ff @(posedge clk_49m) begin
    if (ioctl_wr && (ioctl_index == 8'd1) && (ioctl_addr == 25'd0))
        variant_sel <= ioctl_data[2:0];
end

selector DLSEL
(
	.ioctl_addr(ioctl_addr),
	.main_rom_cs(main_rom_cs_i),
	.sub_rom_cs(sub_rom_cs_i),
	.fg_rom_cs(fg_rom_cs_i),
	.bg0_rom_cs(bg0_rom_cs_i),
	.bg1_rom_cs(bg1_rom_cs_i),
	.bg2_rom_cs(bg2_rom_cs_i),
	.spr0_rom_cs(spr0_rom_cs_i),
	.spr1_rom_cs(spr1_rom_cs_i),
	.spr2_rom_cs(spr2_rom_cs_i),
	.prom_r_cs(prom_r_cs_i),
	.prom_g_cs(prom_g_cs_i),
	.prom_b_cs(prom_b_cs_i),
	.prom_lut_cs(prom_lut_cs_i),
	.prom_tim_cs(prom_tim_cs_i)
);

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// z80_0: main CPU (kyugo board, every variant)
chip_pool_pkg::z80r_i_t z80_0_i;
chip_pool_pkg::z80r_o_t z80_0_o;
wire [15:0] z80_0_a;
wire  [7:0] z80_0_do;
wire        z80_0_m1_n, z80_0_mreq_n, z80_0_iorq_n, z80_0_rd_n, z80_0_wr_n, z80_0_rfsh_n;

t80sv_T80s z80_0
(
	.RESET_n(z80_0_i.reset_n), .CLK(clk_49m), .CEN(z80_0_i.ce), .WAIT_n(1'b1), .BUSRQ_n(1'b1), .OUT0(1'b0),
	.INT_n(z80_0_i.int_n), .NMI_n(z80_0_i.nmi_n),
	.M1_n(z80_0_m1_n), .MREQ_n(z80_0_mreq_n), .IORQ_n(z80_0_iorq_n),
	.RD_n(z80_0_rd_n), .WR_n(z80_0_wr_n), .RFSH_n(z80_0_rfsh_n),
	.A(z80_0_a), .DI(z80_0_i.di), .DO(z80_0_do)
);
assign z80_0_o.a    = z80_0_a;    assign z80_0_o.dout   = z80_0_do;
assign z80_0_o.m1_n = z80_0_m1_n; assign z80_0_o.mreq_n = z80_0_mreq_n; assign z80_0_o.iorq_n = z80_0_iorq_n;
assign z80_0_o.rd_n = z80_0_rd_n; assign z80_0_o.wr_n   = z80_0_wr_n;   assign z80_0_o.rfsh_n = z80_0_rfsh_n;

// z80_1: sub CPU (kyugo board, every variant)
chip_pool_pkg::z80r_i_t z80_1_i;
chip_pool_pkg::z80r_o_t z80_1_o;
wire [15:0] z80_1_a;
wire  [7:0] z80_1_do;
wire        z80_1_m1_n, z80_1_mreq_n, z80_1_iorq_n, z80_1_rd_n, z80_1_wr_n, z80_1_rfsh_n;

t80sv_T80s z80_1
(
	.RESET_n(z80_1_i.reset_n), .CLK(clk_49m), .CEN(z80_1_i.ce), .WAIT_n(1'b1), .BUSRQ_n(1'b1), .OUT0(1'b0),
	.INT_n(z80_1_i.int_n), .NMI_n(z80_1_i.nmi_n),
	.M1_n(z80_1_m1_n), .MREQ_n(z80_1_mreq_n), .IORQ_n(z80_1_iorq_n),
	.RD_n(z80_1_rd_n), .WR_n(z80_1_wr_n), .RFSH_n(z80_1_rfsh_n),
	.A(z80_1_a), .DI(z80_1_i.di), .DO(z80_1_do)
);
assign z80_1_o.a    = z80_1_a;    assign z80_1_o.dout   = z80_1_do;
assign z80_1_o.m1_n = z80_1_m1_n; assign z80_1_o.mreq_n = z80_1_mreq_n; assign z80_1_o.iorq_n = z80_1_iorq_n;
assign z80_1_o.rd_n = z80_1_rd_n; assign z80_1_o.wr_n   = z80_1_wr_n;   assign z80_1_o.rfsh_n = z80_1_rfsh_n;

// ay_0: AY 1, DSW1 / DSW2 on ports A / B (kyugo board, every variant)
chip_pool_pkg::ay_i_t ay_0_i;
chip_pool_pkg::ay_o_t ay_0_o;

jt49_bus ay_0
(
	.rst_n(reset), .clk(clk_49m), .clk_en(ay_0_i.ce), .bdir(ay_0_i.bdir), .bc1(ay_0_i.bc1),
	.din(ay_0_i.din), .dout(ay_0_o.dout), .sel(1'b1),
	.sound(ay_0_o.sound), .sample(), .A(ay_0_o.a), .B(ay_0_o.b), .C(ay_0_o.c),
	.IOA_in(ay_0_i.ioa_in), .IOB_in(ay_0_i.iob_in), .IOA_out(), .IOB_out(ay_0_o.iob_out)
);

// ay_1: AY 2 (kyugo board, every variant)
chip_pool_pkg::ay_i_t ay_1_i;
chip_pool_pkg::ay_o_t ay_1_o;

jt49_bus ay_1
(
	.rst_n(reset), .clk(clk_49m), .clk_en(ay_1_i.ce), .bdir(ay_1_i.bdir), .bc1(ay_1_i.bc1),
	.din(ay_1_i.din), .dout(ay_1_o.dout), .sel(1'b1),
	.sound(ay_1_o.sound), .sample(), .A(ay_1_o.a), .B(ay_1_o.b), .C(ay_1_o.c),
	.IOA_in(ay_1_i.ioa_in), .IOB_in(ay_1_i.iob_in), .IOA_out(), .IOB_out(ay_1_o.iob_out)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////
//   rom 0   32K  main program        0x00000      rom 7   32K  sprite plane 1   0x25000
//   rom 1   32K  sub program         0x08000      rom 8   32K  sprite plane 2   0x2D000
//   rom 2    4K  fg tiles            0x10000      rom 9   256  colour PROM R    0x35000
//   rom 3   16K  bg plane 0          0x11000      rom 10  256  colour PROM G    0x35100
//   rom 4   16K  bg plane 1          0x15000      rom 11  256  colour PROM B    0x35200
//   rom 5   16K  bg plane 2          0x19000      rom 12   32  char lookup PROM 0x35300
//   rom 6   32K  sprite plane 0      0x1D000
wire [14:0] rom0_a, rom1_a, rom6_a, rom7_a, rom8_a;
wire [11:0] rom2_a;
wire [13:0] rom3_a, rom4_a, rom5_a;
wire  [7:0] rom9_a, rom10_a, rom11_a;
wire  [4:0] rom12_a;
wire  [7:0] rom0_d, rom1_d, rom2_d, rom3_d, rom4_d, rom5_d, rom6_d, rom7_d, rom8_d, rom9_d, rom10_d, rom11_d, rom12_d;

eprom_32k rom_0 (.CLK(clk_49m), .ADDR(rom0_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom0_d));
eprom_32k rom_1 (.CLK(clk_49m), .ADDR(rom1_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(sub_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom1_d));
eprom_4k rom_2 (.CLK(clk_49m), .ADDR(rom2_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(fg_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom2_d));
eprom_16k rom_3 (.CLK(clk_49m), .ADDR(rom3_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr - 25'h11000), .DATA_IN(ioctl_data), .CS_DL(bg0_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom3_d));
eprom_16k rom_4 (.CLK(clk_49m), .ADDR(rom4_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr - 25'h15000), .DATA_IN(ioctl_data), .CS_DL(bg1_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom4_d));
eprom_16k rom_5 (.CLK(clk_49m), .ADDR(rom5_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr - 25'h19000), .DATA_IN(ioctl_data), .CS_DL(bg2_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom5_d));
eprom_32k rom_6 (.CLK(clk_49m), .ADDR(rom6_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr - 25'h1D000), .DATA_IN(ioctl_data), .CS_DL(spr0_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom6_d));
eprom_32k rom_7 (.CLK(clk_49m), .ADDR(rom7_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr - 25'h25000), .DATA_IN(ioctl_data), .CS_DL(spr1_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom7_d));
eprom_32k rom_8 (.CLK(clk_49m), .ADDR(rom8_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr - 25'h2D000), .DATA_IN(ioctl_data), .CS_DL(spr2_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(rom8_d));
eprom_256b rom_9 (.CLK(clk_49m), .ADDR(rom9_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_r_cs_i), .WR(ioctl_wr_cpu), .DATA(rom9_d));
eprom_256b rom_10 (.CLK(clk_49m), .ADDR(rom10_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_g_cs_i), .WR(ioctl_wr_cpu), .DATA(rom10_d));
eprom_256b rom_11 (.CLK(clk_49m), .ADDR(rom11_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_b_cs_i), .WR(ioctl_wr_cpu), .DATA(rom11_d));
eprom_32b rom_12 (.CLK(clk_49m), .ADDR(rom12_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_lut_cs_i), .WR(ioctl_wr_cpu), .DATA(rom12_d));

/////////////////////////////  Shared RAM pool  /////////////////////////////
//   pr 0   2K   kyugo: CPU-shared RAM, main F000 (+ E000 SRD Mission) / sub per variant; port A q = hiscore read
//   pr 1   2K   kyugo: BG video RAM 8000
//   pr 2   2K   kyugo: BG attribute RAM 8800
//   pr 3   2K   kyugo: FG video RAM 9000
//   pr 4   2K   kyugo: FG video RAM 9000 shadow (sprite engine read port)
//   pr 5   2K   kyugo: sprite RAM 0 A000
//   pr 6   2K   kyugo: sprite RAM 1 9800
//   pr 7   2K   kyugo: SRD Mission / Airwolf sub-only RAM 8800
localparam int RAM_BLOCKS = 8;
function automatic int ram_aw(input int blk);
	ram_aw = 11;
endfunction

ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;

genvar n;
generate for (n = 0; n < RAM_BLOCKS; n = n + 1) begin : rpool
	dpram_dc #(.widthad_a(ram_aw(n))) pr (
		.clock_a(clk_49m), .address_a(pool_i[n].a_addr[ram_aw(n)-1:0]), .data_a(pool_i[n].a_d), .wren_a(pool_i[n].a_we), .q_a(pool_o[n].a_q),
		.clock_b(clk_49m), .address_b(pool_i[n].b_addr[ram_aw(n)-1:0]), .data_b(pool_i[n].b_d), .wren_b(pool_i[n].b_we), .q_b(pool_o[n].b_q));
end endgenerate

/////////////////////////////  Boards  /////////////////////////////

chip_pool_pkg::z80r_i_t kyugo_z80_0_i, kyugo_z80_1_i;
chip_pool_pkg::ay_i_t   kyugo_ay_0_i, kyugo_ay_1_i;
ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] kyugo_pr_i;

assign z80_0_i = kyugo_z80_0_i;
assign z80_1_i = kyugo_z80_1_i;
assign ay_0_i  = kyugo_ay_0_i;
assign ay_1_i  = kyugo_ay_1_i;
assign pool_i  = kyugo_pr_i;

kyugo_board board
(
	.reset(reset),
	.clk_49m(clk_49m),

	.red(video_r),
	.green(video_g),
	.blue(video_b),
	.video_hsync(video_hsync),
	.video_vsync(video_vsync),
	.video_csync(video_csync),
	.video_hblank(video_hblank),
	.video_vblank(video_vblank),
	.ce_pix(ce_pix),

	.p1_controls(p1_controls),
	.p2_controls(p2_controls),
	.sys_controls(sys_controls),

	.dip_sw(dip_sw),

    .rot_flip(rot_flip),

	.sound(sound),

	.h_center(h_center),
	.v_center(v_center),

	.variant_sel(variant_sel),
	.coin_counter(),

	.pause(pause),

	.hs_address(hs_address),
	.hs_data_out(hs_data_out),
	.hs_data_in(hs_data_in),
	.hs_write(hs_write),

	.z80_0_i(kyugo_z80_0_i), .z80_0_o(z80_0_o), .z80_1_i(kyugo_z80_1_i), .z80_1_o(z80_1_o),
	.ay_0_i(kyugo_ay_0_i), .ay_0_o(ay_0_o), .ay_1_i(kyugo_ay_1_i), .ay_1_o(ay_1_o),
	.rom0_a(rom0_a), .rom0_d(rom0_d), .rom1_a(rom1_a), .rom1_d(rom1_d), .rom2_a(rom2_a), .rom2_d(rom2_d),
	.rom3_a(rom3_a), .rom3_d(rom3_d), .rom4_a(rom4_a), .rom4_d(rom4_d), .rom5_a(rom5_a), .rom5_d(rom5_d),
	.rom6_a(rom6_a), .rom6_d(rom6_d), .rom7_a(rom7_a), .rom7_d(rom7_d), .rom8_a(rom8_a), .rom8_d(rom8_d),
	.rom9_a(rom9_a), .rom9_d(rom9_d), .rom10_a(rom10_a), .rom10_d(rom10_d), .rom11_a(rom11_a), .rom11_d(rom11_d),
	.rom12_a(rom12_a), .rom12_d(rom12_d),
	.pr_i(kyugo_pr_i), .pr_o(pool_o)
);

endmodule
