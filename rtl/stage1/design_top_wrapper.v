`default_nettype wire
`timescale 1ns/1ps

// Stage 1: EF2 + 25 MHz + VexRiscv + Wishbone ROM/RAM/UART.
module design_top_wrapper(
    input  wire clk_ref,
    input  wire i_rst,
    input  wire rx,
    output wire tx
);

    // The supplied TD reference design uses 10 MHz -> 25 MHz.
    wire sys_clk;
    wire sys_rst_n;

    // Hold the PLL in reset briefly after the external reset is released.
    reg [15:0] cnt_rst = 16'd1;
    reg pll_rst = 1'b1;
    reg [2:0] i_rst_sync = 3'b000;

    always @(posedge clk_ref) begin
        i_rst_sync <= {i_rst_sync[1:0], i_rst};
    end

    always @(posedge clk_ref or posedge i_rst_sync[2]) begin
        if (i_rst_sync[2]) begin
            cnt_rst <= 16'd1;
            pll_rst <= 1'b1;
        end else begin
            if (!cnt_rst[15])
                cnt_rst <= cnt_rst << 1;
            pll_rst <= ~cnt_rst[15];
        end
    end

    sys_pll u_sys_pll(
        .refclk   (clk_ref),
        .reset    (pll_rst),
        .stdby    (1'b0),
        .extlock  (sys_rst_n),
        .clk0_out (),
        .clk1_out (sys_clk)
    );

    // CPU reset stays asserted until the PLL reports lock. The JTAG loader can
    // also hold reset while downloading firmware into RAM.
    wire jtag_boot_from_ram;
    wire jtag_hold_reset;
    wire cpu_reset = ~sys_rst_n | jtag_hold_reset;

    wire        cfg_jrstn;
    wire [1:0]  cfg_jrti;
    wire        cfg_jshift;
    wire        cfg_jtck;
    wire        cfg_jtdi;
    wire        cfg_jupdate;
    wire [1:0]  cfg_jscanen;
    wire        cfg_jtms;
    wire        cfg_jtdo;

    EF2_PHY_CONFIG #(
        .JTAG_PERSISTN("ENABLE")
    ) u_jtag_config (
        .jrstn              (cfg_jrstn),
        .jrti               (cfg_jrti),
        .jshift             (cfg_jshift),
        .jtck               (cfg_jtck),
        .jtdi               (cfg_jtdi),
        .jupdate            (cfg_jupdate),
        .jscanen            (cfg_jscanen),
        .jtms               (cfg_jtms),
        .jtdo               ({cfg_jtdo, cfg_jtdo}),
        .jtag8_ipa          (8'b0),
        .jtag8_ipb          (8'b0),
        .mboot_rebootn      (1'b1),
        .mboot_dynamic_addr (8'b0),
        .dna_dout           (),
        .dna_clk            (1'b0),
        .dna_din            (1'b0),
        .dna_shift_en       (1'b0),
        .done               (),
        .highz              (),
        .usr_gsrn           (1'b1),
        .gsrn_sync_clk      (sys_clk),
        .cclk               (),
        .cclk_en            (1'b0)
    );

    // ---------------------------------------------------------------------
    // VexRiscv Wishbone buses
    // ---------------------------------------------------------------------
    wire        ibus_cyc, ibus_stb, ibus_we, ibus_ack, ibus_err;
    wire [29:0] ibus_adr;
    wire [31:0] ibus_dat_miso, ibus_dat_mosi;
    wire [3:0]  ibus_sel;
    wire [1:0]  ibus_bte;
    wire [2:0]  ibus_cti;

    wire        dbus_cyc, dbus_stb, dbus_we, dbus_ack, dbus_err;
    wire [29:0] dbus_adr;
    wire [31:0] dbus_dat_miso, dbus_dat_mosi;
    wire [3:0]  dbus_sel;
    wire [1:0]  dbus_bte;
    wire [2:0]  dbus_cti;

    // ---------------------------------------------------------------------
    // ROM / RAM / UART slave wires
    // ---------------------------------------------------------------------
    wire [31:0] rom_adr, rom_dat, rom_rdat;
    wire [3:0]  rom_sel;
    wire        rom_we, rom_cyc, rom_stb, rom_ack;

    wire [31:0] ram_adr, ram_dat, ram_rdat;
    wire [3:0]  ram_sel;
    wire        ram_we, ram_cyc, ram_stb, ram_ack;

    wire [31:0] jtag_ram_adr, jtag_ram_dat, jtag_ram_rdat;
    wire [3:0]  jtag_ram_sel;
    wire        jtag_ram_we, jtag_ram_cyc, jtag_ram_stb, jtag_ram_ack;

    wire        ram_port_jtag = jtag_ram_cyc;

    wire [31:0] uart_adr, uart_dat, uart_rdat;
    wire [3:0]  uart_sel;
    wire        uart_we, uart_cyc, uart_stb, uart_ack;

    soc_wb_intercon u_intercon (
        .i_ibus_cyc       (ibus_cyc),
        .i_ibus_stb       (ibus_stb),
        .i_ibus_adr       (ibus_adr),
        .i_ibus_dat_mosi  (ibus_dat_mosi),
        .i_ibus_sel       (ibus_sel),
        .i_ibus_we        (ibus_we),
        .o_ibus_ack       (ibus_ack),
        .o_ibus_dat_miso  (ibus_dat_miso),
        .o_ibus_err       (ibus_err),

        .i_dbus_cyc       (dbus_cyc),
        .i_dbus_stb       (dbus_stb),
        .i_dbus_adr       (dbus_adr),
        .i_dbus_dat_mosi  (dbus_dat_mosi),
        .i_dbus_sel       (dbus_sel),
        .i_dbus_we        (dbus_we),
        .o_dbus_ack       (dbus_ack),
        .o_dbus_dat_miso  (dbus_dat_miso),
        .o_dbus_err       (dbus_err),

        .o_rom_adr        (rom_adr),
        .o_rom_dat        (rom_dat),
        .o_rom_sel        (rom_sel),
        .o_rom_we         (rom_we),
        .o_rom_cyc        (rom_cyc),
        .o_rom_stb        (rom_stb),
        .i_rom_dat        (rom_rdat),
        .i_rom_ack        (rom_ack),

        .o_ram_adr        (ram_adr),
        .o_ram_dat        (ram_dat),
        .o_ram_sel        (ram_sel),
        .o_ram_we         (ram_we),
        .o_ram_cyc        (ram_cyc),
        .o_ram_stb        (ram_stb),
        .i_ram_dat        (ram_rdat),
        .i_ram_ack        (ram_ack),

        .o_uart_adr       (uart_adr),
        .o_uart_dat       (uart_dat),
        .o_uart_sel       (uart_sel),
        .o_uart_we        (uart_we),
        .o_uart_cyc       (uart_cyc),
        .o_uart_stb       (uart_stb),
        .i_uart_dat       (uart_rdat),
        .i_uart_ack       (uart_ack)
    );

    // 256-byte ROM (64 x 32-bit words). The test firmware is only 48 words.
    wb_ram #(
        .SIZE(64),
        .INITIAL_HEX("../firmware/soc_fw.hex")
    ) u_rom (
        .i_clk    (sys_clk),
        .i_reset  (cpu_reset),
        .i_wb_adr (rom_adr),
        .i_wb_dat (rom_dat),
        .i_wb_sel (rom_sel),
        .i_wb_we  (rom_we),
        .i_wb_cyc (rom_cyc),
        .i_wb_stb (rom_stb),
        .o_wb_dat (rom_rdat),
        .o_wb_ack (rom_ack)
    );

    // 1 KiB data RAM at 0x8000_0000 (reduced for EF2 resource headroom).
    wb_ram #(
        .SIZE(256)
    ) u_ram (
        .i_clk    (sys_clk),
        .i_reset  (~sys_rst_n),
        .i_wb_adr (ram_port_jtag ? jtag_ram_adr : ram_adr),
        .i_wb_dat (ram_port_jtag ? jtag_ram_dat : ram_dat),
        .i_wb_sel (ram_port_jtag ? jtag_ram_sel : ram_sel),
        .i_wb_we  (ram_port_jtag ? jtag_ram_we  : ram_we),
        .i_wb_cyc (ram_port_jtag ? jtag_ram_cyc : ram_cyc),
        .i_wb_stb (ram_port_jtag ? jtag_ram_stb : ram_stb),
        .o_wb_dat (ram_rdat),
        .o_wb_ack (ram_ack)
    );

    assign jtag_ram_rdat = ram_rdat;
    assign jtag_ram_ack = ram_ack & ram_port_jtag;

    jtag_wb_loader u_jtag_loader (
        .i_clk           (sys_clk),
        .i_reset         (~sys_rst_n),
        .i_jtag_tck      (cfg_jtck),
        .i_jtag_shift    (cfg_jshift & |cfg_jscanen),
        .i_jtag_update   (cfg_jupdate & |cfg_jscanen),
        .i_jtag_tdi      (cfg_jtdi),
        .o_jtag_tdo      (cfg_jtdo),
        .o_wb_cyc        (jtag_ram_cyc),
        .o_wb_stb        (jtag_ram_stb),
        .o_wb_we         (jtag_ram_we),
        .o_wb_adr        (jtag_ram_adr),
        .o_wb_dat        (jtag_ram_dat),
        .o_wb_sel        (jtag_ram_sel),
        .i_wb_dat        (jtag_ram_rdat),
        .i_wb_ack        (jtag_ram_ack),
        .o_boot_from_ram (jtag_boot_from_ram),
        .o_hold_reset    (jtag_hold_reset)
    );

    // 8-bit buffered UART, 115200 baud at 25 MHz.
    // Prescaler = 25,000,000 / 115,200 - 1 ~= 216.
    uart_wb #(
        .TX_BUFSIZE (64),
        .RX_BUFSIZE (8),
        .DATA_WIDTH (8)
    ) u_uart (
        .i_clk     (sys_clk),
        .i_reset   (cpu_reset),
        .i_uart_rx (rx),
        .o_uart_tx (tx),
        .i_wb_adr  (uart_adr),
        .i_wb_dat  (uart_dat),
        .i_wb_sel  (uart_sel),
        .i_wb_we   (uart_we),
        .i_wb_cyc  (uart_cyc),
        .i_wb_stb  (uart_stb),
        .o_wb_dat  (uart_rdat),
        .o_wb_ack  (uart_ack)
    );

    // ---------------------------------------------------------------------
    // VexRiscv CPU
    // ---------------------------------------------------------------------
    VexRiscv cpu0 (
        .clk                 (sys_clk),
        .reset               (cpu_reset),
        .externalResetVector (jtag_boot_from_ram ? 32'h8000_0000 : 32'h2000_0000),
        .timerInterrupt      (1'b0),
        .externalInterrupt   (1'b0),
        .softwareInterrupt   (1'b0),

        .iBusWishbone_CYC        (ibus_cyc),
        .iBusWishbone_STB        (ibus_stb),
        .iBusWishbone_ACK        (ibus_ack),
        .iBusWishbone_WE         (ibus_we),
        .iBusWishbone_ADR        (ibus_adr),
        .iBusWishbone_DAT_MISO   (ibus_dat_miso),
        .iBusWishbone_DAT_MOSI   (ibus_dat_mosi),
        .iBusWishbone_SEL        (ibus_sel),
        .iBusWishbone_ERR        (ibus_err),
        .iBusWishbone_BTE        (ibus_bte),
        .iBusWishbone_CTI        (ibus_cti),

        .dBusWishbone_CYC        (dbus_cyc),
        .dBusWishbone_STB        (dbus_stb),
        .dBusWishbone_ACK        (dbus_ack),
        .dBusWishbone_WE         (dbus_we),
        .dBusWishbone_ADR        (dbus_adr),
        .dBusWishbone_DAT_MISO   (dbus_dat_miso),
        .dBusWishbone_DAT_MOSI   (dbus_dat_mosi),
        .dBusWishbone_SEL        (dbus_sel),
        .dBusWishbone_ERR        (dbus_err),
        .dBusWishbone_BTE        (dbus_bte),
        .dBusWishbone_CTI        (dbus_cti)
    );

endmodule
