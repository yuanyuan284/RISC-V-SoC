module stage2_top #(parameter ENABLE_JTAG = 0)(
    input wire clk_ref, i_rst, rx, output wire tx
);
    reg [2:0] reset_sync = 0;
    reg [15:0] count = 1;
    wire pll_reset = !count[15];
    wire clk, locked;
    always @(posedge clk_ref) begin
        reset_sync <= {reset_sync[1:0], i_rst};
        if (reset_sync[2]) count <= 1;
        else if (!count[15]) count <= count << 1;
    end
    sys_pll pll(.refclk(clk_ref), .reset(pll_reset), .stdby(1'b0),
                .extlock(locked), .clk0_out(), .clk1_out(clk));
    reg [1:0] reset_pipe = 3;
    always @(posedge clk or negedge locked) begin
        if (!locked) reset_pipe <= 3;
        else reset_pipe <= {reset_pipe[0], 1'b0};
    end
    wire reset = reset_pipe[1];
    wire jtag_boot_ram, jtag_hold_reset;
    wire jtag_cyc, jtag_stb, jtag_we, jtag_ack;
    wire [31:0] jtag_addr, jtag_data;
    wire [31:0] rom_data, ram_data, uart_data;
    wire [3:0] jtag_sel;
    wire cpu_reset = reset | jtag_hold_reset;

    generate if (ENABLE_JTAG) begin : jtag
        wire jrstn, jshift, jtck, jtdi, jupdate, jtms, jtdo;
        wire [1:0] jrti, jscanen;
        EF2_PHY_CONFIG #(.JTAG_PERSISTN("ENABLE")) u_config(
            .jrstn(jrstn), .jrti(jrti), .jshift(jshift),
            .jtck(jtck), .jtdi(jtdi), .jupdate(jupdate),
            .jscanen(jscanen), .jtms(jtms), .jtdo({jtdo, jtdo}),
            .jtag8_ipa(8'b0), .jtag8_ipb(8'b0),
            .mboot_rebootn(1'b1), .mboot_dynamic_addr(8'b0),
            .dna_dout(), .dna_clk(1'b0), .dna_din(1'b0),
            .dna_shift_en(1'b0), .done(), .highz(),
            .usr_gsrn(1'b1), .gsrn_sync_clk(clk),
            .cclk(), .cclk_en(1'b0)
        );
        jtag_wb_loader loader(
            .i_clk(clk), .i_reset(reset), .i_jtag_tck(jtck),
            .i_jtag_shift(jshift & |jscanen),
            .i_jtag_update(jupdate & |jscanen), .i_jtag_tdi(jtdi),
            .o_jtag_tdo(jtdo), .o_wb_cyc(jtag_cyc),
            .o_wb_stb(jtag_stb), .o_wb_we(jtag_we),
            .o_wb_adr(jtag_addr), .o_wb_dat(jtag_data),
            .o_wb_sel(jtag_sel), .i_wb_dat(ram_data),
            .i_wb_ack(jtag_ack), .o_boot_from_ram(jtag_boot_ram),
            .o_hold_reset(jtag_hold_reset)
        );
    end else begin : no_jtag
        assign jtag_boot_ram = 1'b0;
        assign jtag_hold_reset = 1'b0;
        assign jtag_cyc = 1'b0;
        assign jtag_stb = 1'b0;
        assign jtag_we = 1'b0;
        assign jtag_addr = 32'b0;
        assign jtag_data = 32'b0;
        assign jtag_sel = 4'b0;
    end endgenerate

    wire ic, is, iw, ia, ie, dc, ds, dw, da, de;
    wire [29:0] iad, dad;
    wire [31:0] idw, ddw, read_data;
    wire [3:0] ise, dse;
    // Keep ownership until CYC drops, including the eight-beat I-cache refill.
    reg active = 0, data_owner = 0;
    always @(posedge clk) begin
        if (cpu_reset) begin active <= 0; data_owner <= 0; end
        else if (active) begin
            if (!(data_owner ? dc : ic)) active <= 0;
        end else if (dc || ic) begin
            active <= 1;
            data_owner <= dc;
        end
    end
    wire cycle = active && (data_owner ? dc : ic);
    wire strobe = data_owner ? ds : is;
    wire write_enable = data_owner ? dw : iw;
    wire [31:0] address = {data_owner ? dad : iad, 2'b00};
    wire [31:0] write_data = data_owner ? ddw : idw;
    wire [3:0] select = data_owner ? dse : ise;
    wire rom_select = address[31:10] == (32'h20000000 >> 10);
    wire ram_select = address[31:10] == (32'h80000000 >> 10);
    wire uart_select = address[31:12] == (32'h40001000 >> 12);
    wire rom_ack, ram_ack, uart_ack;
    wire fault = cycle && strobe &&
        (!(rom_select || ram_select || uart_select) || (rom_select && write_enable));
    wire ack = cycle && strobe && !fault &&
        ((rom_select && rom_ack) ||
         (ram_select && ram_ack && !jtag_cyc) ||
         (uart_select && uart_ack));
    assign jtag_ack = jtag_cyc && ram_ack;
    assign read_data = rom_select ? rom_data : ram_select ? ram_data : uart_data;
    assign ia = ack && !data_owner;
    assign da = ack && data_owner;
    assign ie = fault && !data_owner;
    assign de = fault && data_owner;
    stage2_memory #(.READ_ONLY(1), .HEX_FILE("../build/bootrom.hex")) rom(
        .clk(clk), .reset(reset), .address(address), .write_data(write_data),
        .select(select), .write_enable(1'b0), .cycle(cycle && rom_select && !write_enable),
        .strobe(strobe), .read_data(rom_data), .ack(rom_ack));
    stage2_memory ram(
        .clk(clk), .reset(reset),
        .address(jtag_cyc ? jtag_addr : address),
        .write_data(jtag_cyc ? jtag_data : write_data),
        .select(jtag_cyc ? jtag_sel : select),
        .write_enable(jtag_cyc ? jtag_we : write_enable),
        .cycle(jtag_cyc || (cycle && ram_select)),
        .strobe(jtag_cyc ? jtag_stb : strobe),
        .read_data(ram_data), .ack(ram_ack));
    uart_wb #(.TX_BUFSIZE(8), .RX_BUFSIZE(8), .DATA_WIDTH(8)) uart(
        .i_clk(clk), .i_reset(reset), .i_uart_rx(rx), .o_uart_tx(tx),
        .i_wb_adr(address), .i_wb_dat(write_data), .i_wb_sel(select),
        .i_wb_we(write_enable), .i_wb_cyc(cycle && uart_select), .i_wb_stb(strobe),
        .o_wb_dat(uart_data), .o_wb_ack(uart_ack));
    VexRiscv cpu(
        .clk(clk), .reset(cpu_reset),
        .externalResetVector(jtag_boot_ram ? 32'h80000000 : 32'h20000000),
        .timerInterrupt(1'b0), .externalInterrupt(1'b0), .softwareInterrupt(1'b0),
        .iBusWishbone_CYC(ic), .iBusWishbone_STB(is), .iBusWishbone_WE(iw),
        .iBusWishbone_ADR(iad), .iBusWishbone_DAT_MOSI(idw), .iBusWishbone_SEL(ise),
        .iBusWishbone_ACK(ia), .iBusWishbone_ERR(ie), .iBusWishbone_DAT_MISO(read_data),
        .iBusWishbone_BTE(), .iBusWishbone_CTI(),
        .dBusWishbone_CYC(dc), .dBusWishbone_STB(ds), .dBusWishbone_WE(dw),
        .dBusWishbone_ADR(dad), .dBusWishbone_DAT_MOSI(ddw), .dBusWishbone_SEL(dse),
        .dBusWishbone_ACK(da), .dBusWishbone_ERR(de), .dBusWishbone_DAT_MISO(read_data),
        .dBusWishbone_BTE(), .dBusWishbone_CTI());
endmodule

module stage2_jtag_top(input wire clk_ref, i_rst, rx, output wire tx);
    stage2_top #(.ENABLE_JTAG(1)) core(
        .clk_ref(clk_ref), .i_rst(i_rst), .rx(rx), .tx(tx)
    );
endmodule
