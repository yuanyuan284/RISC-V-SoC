// Experimental single-hart RTOS + XIP + independent JTAG variant.
module stage3_unified_top(
    input wire clk_ref, i_rst, rx,
    output wire tx,
    input wire jtag_tck, jtag_tms, jtag_tdi,
    output wire jtag_tdo
);
    reg [15:0] startup = 1;
    always @(posedge clk_ref)
        if (!startup[15]) startup <= startup << 1;
    wire clk, locked;
    sys_pll pll(.refclk(clk_ref), .reset(!startup[15]), .stdby(1'b0),
        .extlock(locked), .clk0_out(), .clk1_out(clk));
    reg [1:0] power_pipe = 3;
    reg [2:0] button_pipe = 0;
    always @(posedge clk or negedge locked) begin
        if (!locked) begin power_pipe <= 3; button_pipe <= 0; end
        else begin
            power_pipe <= {power_pipe[0], 1'b0};
            button_pipe <= {button_pipe[1:0], i_rst};
        end
    end

    wire flash_cs_n, flash_sck, flash_mosi, flash_miso;
    wire flash_io0, flash_io1, flash_io2, flash_io3;
    assign flash_io0 = flash_mosi;
    assign flash_io2 = 1'b1;
    assign flash_io3 = 1'b1;
    assign flash_miso = flash_io1;
    EF2_PHY_INTFLASH flash_pins(.mosi_io0(flash_io0), .miso_io1(flash_io1),
        .wp_n_io2(flash_io2), .hold_n_io3(flash_io3),
        .cclk(flash_sck), .cs_n(flash_cs_n));

    stage3_unified_soc soc(.clk(clk), .power_reset(power_pipe[1]),
        .board_reset(button_pipe[2]), .rx(rx), .tx(tx),
        .jtag_tck(jtag_tck), .jtag_tms(jtag_tms),
        .jtag_tdi(jtag_tdi), .jtag_tdo(jtag_tdo),
        .flash_cs_n(flash_cs_n), .flash_sck(flash_sck),
        .flash_mosi(flash_mosi), .flash_miso(flash_miso));
endmodule

module stage3_unified_soc #(parameter [31:0] RESET_VECTOR = 32'h20000000)(
    input wire clk, power_reset, board_reset, rx,
    output wire tx,
    input wire jtag_tck, jtag_tms, jtag_tdi,
    output wire jtag_tdo,
    output wire flash_cs_n, flash_sck, flash_mosi,
    input wire flash_miso
);
    wire ndmreset, stop_time;
    wire reset = power_reset | board_reset | ndmreset;
    wire ic, is, iw, ia, ie, dc, ds, dw, da, de;
    wire [29:0] iad, dad;
    wire [31:0] idw, ddw, read_data;
    wire [3:0] ise, dse;
    reg active = 0, data_owner = 0;
    always @(posedge clk) begin
        if (reset) begin active <= 0; data_owner <= 0; end
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
    wire rom_select = address[31:13] == (32'h20000000 >> 13);
    wire ram_select = address[31:16] == (32'h80000000 >> 16);
    wire uart_select = address[31:12] == (32'h40001000 >> 12);
    wire clint_select = address[31:16] == 16'h0200;
    wire plic_select = address[31:22] == (32'h0c000000 >> 22);
    wire event_select = address == 32'h40002000;
    wire flash_count_select = address[31:12] == (32'h40003000 >> 12);
    wire flash_writer_select = address[31:12] == (32'h40004000 >> 12);
    wire flash_select = address[31:19] == (32'h30000000 >> 19);
    wire [31:0] rom_data, ram_data, uart_data, clint_data, plic_data;
    wire [31:0] event_data, flash_data, flash_read_count, flash_writer_data;
    wire rom_ack, ram_ack, uart_ack, clint_ack, plic_ack, event_ack;
    wire flash_ack, flash_writer_ack, flash_writer_busy;
    wire timer_irq, software_irq, external_irq, uart_irq, event_irq;
    wire reader_cs_n, reader_sck, reader_mosi;
    wire writer_cs_n, writer_sck, writer_mosi;
    reg flash_count_ack = 0;
    always @(posedge clk) begin
        if (reset) flash_count_ack <= 0;
        else flash_count_ack <= cycle && strobe && flash_count_select &&
                                !flash_count_ack;
    end
    wire fault = cycle && strobe &&
        (!(rom_select || ram_select || uart_select || clint_select ||
           plic_select || event_select || flash_count_select ||
           flash_writer_select || flash_select) ||
         ((rom_select || flash_select || flash_count_select) && write_enable));
    wire ack = cycle && strobe && !fault &&
        ((rom_select && rom_ack) || (ram_select && ram_ack) ||
         (uart_select && uart_ack) || (clint_select && clint_ack) ||
         (plic_select && plic_ack) || (event_select && event_ack) ||
         (flash_select && flash_ack) ||
         (flash_count_select && flash_count_ack) ||
         (flash_writer_select && flash_writer_ack));
    assign read_data = rom_select ? rom_data : ram_select ? ram_data :
        uart_select ? uart_data : clint_select ? clint_data :
        plic_select ? plic_data : event_select ? event_data :
        flash_count_select ? flash_read_count :
        flash_writer_select ? flash_writer_data : flash_data;
    assign ia = ack && !data_owner;
    assign da = ack && data_owner;
    assign ie = fault && !data_owner;
    assign de = fault && data_owner;

    stage3_rom rom(.clk(clk), .reset(reset), .address(address[12:2]),
        .cycle(cycle && rom_select && !write_enable), .strobe(strobe),
        .read_data(rom_data), .ack(rom_ack));
    stage3_ram ram(.clk(clk), .reset(reset), .address(address[15:2]),
        .cycle(cycle && ram_select), .strobe(strobe), .write_enable(write_enable),
        .select(select), .write_data(write_data), .read_data(ram_data), .ack(ram_ack));
    uart_wb #(.TX_BUFSIZE(8), .RX_BUFSIZE(8), .DATA_WIDTH(8)) uart(
        .i_clk(clk), .i_reset(reset), .i_uart_rx(rx), .o_uart_tx(tx),
        .o_irq_rx(uart_irq), .i_wb_adr(address), .i_wb_dat(write_data),
        .i_wb_sel(select), .i_wb_we(write_enable),
        .i_wb_cyc(cycle && uart_select), .i_wb_stb(strobe),
        .o_wb_dat(uart_data), .o_wb_ack(uart_ack));
    rtos_clint clint(.clk(clk), .reset(reset), .stop_time(stop_time),
        .address(address[15:0]),
        .cycle(cycle && clint_select), .strobe(strobe),
        .write_enable(write_enable), .select(select), .write_data(write_data),
        .read_data(clint_data), .ack(clint_ack),
        .timer_irq(timer_irq), .software_irq(software_irq));
    rtos_plic plic(.clk(clk), .reset(reset), .address(address[21:0]),
        .cycle(cycle && plic_select), .strobe(strobe),
        .write_enable(write_enable), .select(select), .write_data(write_data),
        .read_data(plic_data), .ack(plic_ack),
        .sources({event_irq, uart_irq}), .external_irq(external_irq));
    rtos_event event_source(.clk(clk), .reset(reset),
        .cycle(cycle && event_select), .strobe(strobe),
        .write_enable(write_enable), .select(select), .write_data(write_data),
        .read_data(event_data), .ack(event_ack), .irq(event_irq));
    stage3_flash_read flash(.clk(clk), .reset(reset),
        .cycle(cycle && flash_select && !write_enable && !flash_writer_busy),
        .strobe(strobe), .address(address[18:2]), .read_data(flash_data),
        .read_count(flash_read_count), .ack(flash_ack),
        .spi_cs_n(reader_cs_n), .spi_sck(reader_sck),
        .spi_mosi(reader_mosi), .spi_miso(flash_miso));
    stage3_flash_writer writer(.clk(clk), .reset(power_reset),
        .cycle(cycle && flash_writer_select), .strobe(strobe),
        .write_enable(write_enable), .reg_address(address[3:0]),
        .select(select), .write_data(write_data),
        .read_data(flash_writer_data), .ack(flash_writer_ack),
        .busy(flash_writer_busy), .spi_cs_n(writer_cs_n),
        .spi_sck(writer_sck), .spi_mosi(writer_mosi), .spi_miso(flash_miso));
    assign flash_cs_n = flash_writer_busy ? writer_cs_n : reader_cs_n;
    assign flash_sck = flash_writer_busy ? writer_sck : reader_sck;
    assign flash_mosi = flash_writer_busy ? writer_mosi : reader_mosi;

    VexRiscvUnified cpu(.clk(clk), .reset(reset), .debugReset(power_reset),
        .ndmreset(ndmreset), .stoptime(stop_time),
        .externalResetVector(RESET_VECTOR),
        .jtag_tck(jtag_tck), .jtag_tms(jtag_tms), .jtag_tdi(jtag_tdi),
        .jtag_tdo(jtag_tdo), .timerInterrupt(timer_irq),
        .externalInterrupt(external_irq), .softwareInterrupt(software_irq),
        .iBusWishbone_CYC(ic), .iBusWishbone_STB(is), .iBusWishbone_WE(iw),
        .iBusWishbone_ADR(iad), .iBusWishbone_DAT_MOSI(idw),
        .iBusWishbone_SEL(ise), .iBusWishbone_ACK(ia),
        .iBusWishbone_ERR(ie), .iBusWishbone_DAT_MISO(read_data),
        .iBusWishbone_BTE(), .iBusWishbone_CTI(),
        .dBusWishbone_CYC(dc), .dBusWishbone_STB(ds), .dBusWishbone_WE(dw),
        .dBusWishbone_ADR(dad), .dBusWishbone_DAT_MOSI(ddw),
        .dBusWishbone_SEL(dse), .dBusWishbone_ACK(da),
        .dBusWishbone_ERR(de), .dBusWishbone_DAT_MISO(read_data),
        .dBusWishbone_BTE(), .dBusWishbone_CTI());
endmodule
