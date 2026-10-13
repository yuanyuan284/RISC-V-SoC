`default_nettype wire

// Minimal Wishbone address decoder for the first EF2/VexRiscv bring-up.
// Address map:
//   0x2000_0000 - 0x2000_00FF : ROM (instruction + read-only data)
//   0x4000_1000 - 0x4000_1FFF : UART
//   0x8000_0000 - 0x8000_07FF : RAM
module soc_wb_intercon (
    // Instruction master
    input  wire        i_ibus_cyc,
    input  wire        i_ibus_stb,
    input  wire [29:0] i_ibus_adr,
    input  wire [31:0] i_ibus_dat_mosi,
    input  wire [3:0]  i_ibus_sel,
    input  wire        i_ibus_we,
    output wire        o_ibus_ack,
    output wire [31:0] o_ibus_dat_miso,
    output wire        o_ibus_err,

    // Data master
    input  wire        i_dbus_cyc,
    input  wire        i_dbus_stb,
    input  wire [29:0] i_dbus_adr,
    input  wire [31:0] i_dbus_dat_mosi,
    input  wire [3:0]  i_dbus_sel,
    input  wire        i_dbus_we,
    output wire        o_dbus_ack,
    output wire [31:0] o_dbus_dat_miso,
    output wire        o_dbus_err,

    // ROM slave
    output wire [31:0] o_rom_adr,
    output wire [31:0] o_rom_dat,
    output wire [3:0]  o_rom_sel,
    output wire        o_rom_we,
    output wire        o_rom_cyc,
    output wire        o_rom_stb,
    input  wire [31:0] i_rom_dat,
    input  wire        i_rom_ack,

    // RAM slave
    output wire [31:0] o_ram_adr,
    output wire [31:0] o_ram_dat,
    output wire [3:0]  o_ram_sel,
    output wire        o_ram_we,
    output wire        o_ram_cyc,
    output wire        o_ram_stb,
    input  wire [31:0] i_ram_dat,
    input  wire        i_ram_ack,

    // UART slave
    output wire [31:0] o_uart_adr,
    output wire [31:0] o_uart_dat,
    output wire [3:0]  o_uart_sel,
    output wire        o_uart_we,
    output wire        o_uart_cyc,
    output wire        o_uart_stb,
    input  wire [31:0] i_uart_dat,
    input  wire        i_uart_ack
);

    wire [31:0] ibus_addr = {i_ibus_adr, 2'b00};
    wire [31:0] dbus_addr = {i_dbus_adr, 2'b00};

    wire ibus_rom_sel = (ibus_addr >= 32'h2000_0000) && (ibus_addr < 32'h2000_1000);
    wire ibus_ram_sel = (ibus_addr >= 32'h8000_0000) && (ibus_addr < 32'h8000_0800);
    wire dbus_rom_sel = (dbus_addr >= 32'h2000_0000) && (dbus_addr < 32'h2000_1000);
    wire dbus_uart_sel = (dbus_addr >= 32'h4000_1000) && (dbus_addr < 32'h4000_2000);
    wire dbus_ram_sel = (dbus_addr >= 32'h8000_0000) && (dbus_addr < 32'h8000_0800);

    assign o_rom_adr = ibus_rom_sel ? ibus_addr : dbus_addr;
    assign o_rom_dat = i_dbus_dat_mosi;
    assign o_rom_sel = i_ibus_cyc ? i_ibus_sel : i_dbus_sel;
    assign o_rom_we  = i_ibus_cyc ? i_ibus_we : i_dbus_we;
    assign o_rom_cyc = i_ibus_cyc ? ibus_rom_sel : (i_dbus_cyc && dbus_rom_sel);
    assign o_rom_stb = i_ibus_cyc ? (i_ibus_stb && ibus_rom_sel) : (i_dbus_stb && dbus_rom_sel);

    assign o_ram_adr = ibus_ram_sel ? ibus_addr : dbus_addr;
    assign o_ram_dat = i_dbus_dat_mosi;
    assign o_ram_sel = ibus_ram_sel ? i_ibus_sel : i_dbus_sel;
    assign o_ram_we  = ibus_ram_sel ? i_ibus_we : i_dbus_we;
    assign o_ram_cyc = (i_ibus_cyc && ibus_ram_sel) || (i_dbus_cyc && dbus_ram_sel);
    assign o_ram_stb = (i_ibus_stb && ibus_ram_sel) || (i_dbus_stb && dbus_ram_sel);

    assign o_uart_adr = dbus_addr;
    assign o_uart_dat = i_dbus_dat_mosi;
    assign o_uart_sel = i_dbus_sel;
    assign o_uart_we  = i_dbus_we;
    assign o_uart_cyc = i_dbus_cyc && dbus_uart_sel;
    assign o_uart_stb = i_dbus_stb && dbus_uart_sel;

    assign o_ibus_ack = (i_rom_ack && ibus_rom_sel) ||
                        (i_ram_ack && ibus_ram_sel);
    assign o_ibus_dat_miso = ibus_rom_sel ? i_rom_dat :
                             ibus_ram_sel ? i_ram_dat :
                             32'h0000_0000;
    assign o_dbus_ack = (i_rom_ack && dbus_rom_sel) ||
                        (i_ram_ack && dbus_ram_sel) ||
                        (i_uart_ack && dbus_uart_sel);
    assign o_dbus_dat_miso = dbus_rom_sel ? i_rom_dat :
                             dbus_ram_sel ? i_ram_dat :
                             dbus_uart_sel ? i_uart_dat :
                             32'h0000_0000;

    // No bus error generation in stage 1. Unsupported addresses will wait;
    // firmware used for this bring-up only touches ROM/RAM/UART.
    assign o_ibus_err = 1'b0;
    assign o_dbus_err = 1'b0;

endmodule
