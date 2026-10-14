`timescale 1ns/1ps
`default_nettype none

// Minimal RTL simulation for the Stage-1 tiny VexRiscv core.
// Purpose: prove that reset -> instruction fetch -> execute -> UART stores
// are actually happening, without involving the PLL or physical FPGA board.
//
// Add this file to the TD simulation sources together with VexRiscv.v.
// Put soc_fw.hex in the same simulation working directory, or change the
// $readmemh path below.

module VexRiscv_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;

    always #20 clk = ~clk;       // 25 MHz equivalent: 40 ns period

    wire        ibus_cyc;
    wire        ibus_stb;
    wire        ibus_ack;
    wire        ibus_we;
    wire [29:0] ibus_adr;
    wire [31:0] ibus_dat_mosi;
    wire [3:0]  ibus_sel;
    wire        ibus_err;
    wire [1:0]  ibus_bte;
    wire [2:0]  ibus_cti;

    wire        dbus_cyc;
    wire        dbus_stb;
    reg         dbus_ack = 1'b0;
    wire        dbus_we;
    wire [29:0] dbus_adr;
    wire [31:0] dbus_dat_mosi;
    wire [3:0]  dbus_sel;
    wire        dbus_err = 1'b0;
    wire [1:0]  dbus_bte;
    wire [2:0]  dbus_cti;

    // Tiny ROM containing the supplied Stage-1 firmware.
    reg [31:0] rom [0:63];
    wire [31:0] rom_addr = {ibus_adr, 2'b00};
    wire [31:0] rom_index = (rom_addr - 32'h2000_0000) >> 2;

    assign ibus_ack      = ibus_cyc && ibus_stb;
    assign ibus_dat_mosi = 32'b0;
    assign ibus_sel      = 4'b1111;
    assign ibus_we       = 1'b0;
    assign ibus_err      = 1'b0;
    assign ibus_bte      = 2'b00;
    assign ibus_cti      = 3'b000;

    wire [31:0] rom_data =
        (rom_index < 64) ? rom[rom_index[5:0]] : 32'h0000_0013;

    assign dbus_bte = 2'b00;
    assign dbus_cti = 3'b000;

    VexRiscv dut (
        .externalResetVector(32'h2000_0000),
        .timerInterrupt(1'b0),
        .externalInterrupt(1'b0),
        .softwareInterrupt(1'b0),

        .iBusWishbone_CYC(ibus_cyc),
        .iBusWishbone_STB(ibus_stb),
        .iBusWishbone_ACK(ibus_ack),
        .iBusWishbone_WE(ibus_we),
        .iBusWishbone_ADR(ibus_adr),
        .iBusWishbone_DAT_MISO(rom_data),
        .iBusWishbone_DAT_MOSI(ibus_dat_mosi),
        .iBusWishbone_SEL(ibus_sel),
        .iBusWishbone_ERR(ibus_err),
        .iBusWishbone_BTE(ibus_bte),
        .iBusWishbone_CTI(ibus_cti),

        .dBusWishbone_CYC(dbus_cyc),
        .dBusWishbone_STB(dbus_stb),
        .dBusWishbone_ACK(dbus_ack),
        .dBusWishbone_WE(dbus_we),
        .dBusWishbone_ADR(dbus_adr),
        .dBusWishbone_DAT_MISO(32'b0),
        .dBusWishbone_DAT_MOSI(dbus_dat_mosi),
        .dBusWishbone_SEL(dbus_sel),
        .dBusWishbone_ERR(dbus_err),
        .dBusWishbone_BTE(dbus_bte),
        .dBusWishbone_CTI(dbus_cti),

        .clk(clk),
        .reset(reset)
    );

    integer i;
    integer uart_writes;

    initial begin
        for (i = 0; i < 64; i = i + 1)
            rom[i] = 32'h0000_0013;

        $readmemh("soc_fw.hex", rom);
        uart_writes = 0;

        // Keep reset asserted briefly, then release it.
        #200;
        reset = 1'b0;

        // Enough time for the whole firmware string to execute.
        #20000;

        $display("--------------------------------------------------");
        $display("RTL CPU simulation finished.");
        $display("PC  = %h", dut.pc);
        $display("INS = %h", dut.instr);
        $display("UART writes observed = %0d", uart_writes);
        $display("--------------------------------------------------");
        $finish;
    end

    // Simple one-cycle data-bus acknowledge.
    always @(posedge clk) begin
        dbus_ack <= dbus_cyc && dbus_stb;
    end

    // Observe UART writes. The firmware uses 0x4000_1000 as its UART base.
    always @(posedge clk) begin
        if (!reset && dbus_cyc && dbus_stb && dbus_we && dbus_ack) begin
            if ({dbus_adr,2'b00} >= 32'h4000_1000 &&
                {dbus_adr,2'b00} <  32'h4000_2000) begin
                uart_writes = uart_writes + 1;
                $display("[%0t ns] UART WRITE addr=%h data=%h char=%c",
                         $time,
                         {dbus_adr,2'b00},
                         dbus_dat_mosi,
                         dbus_dat_mosi[7:0]);
            end
        end
    end

endmodule

`default_nettype wire
