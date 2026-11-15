//============================================================================
//  board_template.sv - Kyugo core board template (NOT in files.qip, never compiled)
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports. Copy this file to start
//  a board.
//  Pools (rtl/kyugo_dispatcher.sv): z80_0 / z80_1 (z80r_*), ay_0 / ay_1 (ay_*), ROM blocks rom0-rom12 (loaded by
//  ioctl index 0 address only), RAM pool pr 0-7 (2K each, ram_pool_pkg). A new board goes in its own folder
//  rtl/boards/<board>/, is listed in files.qip and replaces its tie-off in the dispatcher's Boards section, where
//  its buses are muxed by variant. A RAM / chip that truly can't pool: "// POOL-EXCEPTION: <reason>" on the line and a
//  Pool contract row. verilator/common/pool_check.sh (POOL_MODS in verilator/Makefile) enforces it.
//============================================================================

module board_template
(
    input  logic        clk_49m,
    input  logic        reset,          // active low
    input  logic        ce,

    output chip_pool_pkg::z80r_i_t z80_0_i,
    input  chip_pool_pkg::z80r_o_t z80_0_o,
    output chip_pool_pkg::z80r_i_t z80_1_i,
    input  chip_pool_pkg::z80r_o_t z80_1_o,
    output chip_pool_pkg::ay_i_t   ay_0_i,
    input  chip_pool_pkg::ay_o_t   ay_0_o,
    output chip_pool_pkg::ay_i_t   ay_1_i,
    input  chip_pool_pkg::ay_o_t   ay_1_o,

    output logic [14:0] rom0_a,  input logic [7:0] rom0_d,
    output logic [14:0] rom1_a,  input logic [7:0] rom1_d,
    output logic [11:0] rom2_a,  input logic [7:0] rom2_d,
    output logic [13:0] rom3_a,  input logic [7:0] rom3_d,
    output logic [13:0] rom4_a,  input logic [7:0] rom4_d,
    output logic [13:0] rom5_a,  input logic [7:0] rom5_d,
    output logic [14:0] rom6_a,  input logic [7:0] rom6_d,
    output logic [14:0] rom7_a,  input logic [7:0] rom7_d,
    output logic [14:0] rom8_a,  input logic [7:0] rom8_d,
    output logic  [7:0] rom9_a,  input logic [7:0] rom9_d,
    output logic  [7:0] rom10_a, input logic [7:0] rom10_d,
    output logic  [7:0] rom11_a, input logic [7:0] rom11_d,
    output logic  [4:0] rom12_a, input logic [7:0] rom12_d,

    output ram_pool_pkg::pram_i_t [7:0] pr_i,
    input  ram_pool_pkg::pram_o_t [7:0] pr_o,

    output logic  [4:0] red, green, blue,
    output logic        video_hsync, video_vsync, video_hblank, video_vblank, ce_pix,
    output logic signed [15:0] sound
);

endmodule
