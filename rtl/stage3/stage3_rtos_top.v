module stage3_rtos_top(input wire clk_ref, i_rst, rx, output wire tx);
    reg [2:0] reset_sync = 0;
    reg [15:0] count = 1;
    wire clk, locked;
    always @(posedge clk_ref) begin
        reset_sync <= {reset_sync[1:0], i_rst};
        if (reset_sync[2]) count <= 1;
        else if (!count[15]) count <= count << 1;
    end
    sys_pll pll(.refclk(clk_ref), .reset(!count[15]), .stdby(1'b0),
        .extlock(locked), .clk0_out(), .clk1_out(clk));
    reg [1:0] reset_pipe = 3;
    always @(posedge clk or negedge locked) begin
        if (!locked) reset_pipe <= 3;
        else reset_pipe <= {reset_pipe[0], 1'b0};
    end
    stage3_rtos_soc soc(.clk(clk), .reset(reset_pipe[1]),
        .reset_vector(32'h20000000), .rx(rx), .tx(tx));
endmodule

module stage3_rtos_soc(
    input wire clk, reset, rx,
    input wire [31:0] reset_vector,
    output wire tx
);
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
            active <= 1; data_owner <= dc;
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
    wire [31:0] rom_data, ram_data, uart_data, clint_data, plic_data, event_data;
    wire rom_ack, ram_ack, uart_ack, clint_ack, plic_ack, event_ack;
    wire timer_irq, software_irq, external_irq, uart_irq, event_irq;
    wire fault = cycle && strobe &&
        (!(rom_select || ram_select || uart_select || clint_select || plic_select ||
            event_select) || (rom_select && write_enable));
    wire ack = cycle && strobe && !fault &&
        ((rom_select && rom_ack) || (ram_select && ram_ack) ||
         (uart_select && uart_ack) || (clint_select && clint_ack) ||
         (plic_select && plic_ack) || (event_select && event_ack));
    assign read_data = rom_select ? rom_data : ram_select ? ram_data :
        uart_select ? uart_data : clint_select ? clint_data :
        plic_select ? plic_data : event_data;
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
        .i_clk(clk), .i_reset(reset), .i_uart_rx(rx), .o_uart_tx(tx), .o_irq_rx(uart_irq),
        .i_wb_adr(address), .i_wb_dat(write_data), .i_wb_sel(select),
        .i_wb_we(write_enable), .i_wb_cyc(cycle && uart_select), .i_wb_stb(strobe),
        .o_wb_dat(uart_data), .o_wb_ack(uart_ack));
    rtos_clint clint(.clk(clk), .reset(reset), .stop_time(1'b0),
        .address(address[15:0]),
        .cycle(cycle && clint_select), .strobe(strobe), .write_enable(write_enable),
        .select(select), .write_data(write_data), .read_data(clint_data), .ack(clint_ack),
        .timer_irq(timer_irq), .software_irq(software_irq));
    rtos_plic plic(.clk(clk), .reset(reset), .address(address[21:0]),
        .cycle(cycle && plic_select), .strobe(strobe), .write_enable(write_enable),
        .select(select), .write_data(write_data), .read_data(plic_data), .ack(plic_ack),
        .sources({event_irq, uart_irq}), .external_irq(external_irq));
    rtos_event event_source(.clk(clk), .reset(reset), .cycle(cycle && event_select),
        .strobe(strobe), .write_enable(write_enable), .select(select),
        .write_data(write_data), .read_data(event_data), .ack(event_ack), .irq(event_irq));
    VexRiscvRtos cpu(.clk(clk), .reset(reset), .externalResetVector(reset_vector),
        .timerInterrupt(timer_irq), .externalInterrupt(external_irq), .softwareInterrupt(software_irq),
        .iBusWishbone_CYC(ic), .iBusWishbone_STB(is), .iBusWishbone_WE(iw),
        .iBusWishbone_ADR(iad), .iBusWishbone_DAT_MOSI(idw), .iBusWishbone_SEL(ise),
        .iBusWishbone_ACK(ia), .iBusWishbone_ERR(ie), .iBusWishbone_DAT_MISO(read_data),
        .iBusWishbone_BTE(), .iBusWishbone_CTI(),
        .dBusWishbone_CYC(dc), .dBusWishbone_STB(ds), .dBusWishbone_WE(dw),
        .dBusWishbone_ADR(dad), .dBusWishbone_DAT_MOSI(ddw), .dBusWishbone_SEL(dse),
        .dBusWishbone_ACK(da), .dBusWishbone_ERR(de), .dBusWishbone_DAT_MISO(read_data),
        .dBusWishbone_BTE(), .dBusWishbone_CTI());
endmodule
