`timescale 1ns/1ps
module tb_flash_remote;
    reg clk = 0, power_reset = 1, tck = 0, tms = 1, tdi = 0;
    wire tdo, tx, spi_cs_n, spi_sck, spi_mosi;
    reg spi_miso = 1;
    reg [7:0] flash [0:524287];
    reg [31:0] command = 0;
    integer command_bits = 0, data_bits = 0;
    reg [18:0] flash_address = 0;
    integer control, image_bytes;

    always #20 clk = ~clk;
    stage3_debug_soc #(.FLASH_READ(1)) dut(.clk(clk),
        .power_reset(power_reset), .board_reset(1'b0),
        .rx(1'b1), .tx(tx), .jtag_tck(tck), .jtag_tms(tms),
        .jtag_tdi(tdi), .jtag_tdo(tdo), .flash_cs_n(spi_cs_n),
        .flash_sck(spi_sck), .flash_mosi(spi_mosi), .flash_miso(spi_miso));

    initial if ($test$plusargs("WAVE")) begin
        $dumpfile("flash_jtag.vcd");
        $dumpvars(0, clk, power_reset, tck, tms, tdi, tdo,
                  dut.cpu.debugTransportModuleJtagTap_1.tap_fsm_state,
                  dut.cpu.debugTransportModuleJtagTap_1.tap_instruction,
                  dut.cpu.debugTransportModuleJtagTap_1.logic_jtagLogic_dmi_logic_store,
                  dut.cycle, dut.strobe, dut.address, dut.ack,
                  dut.flash_select, dut.flash_read_count,
                  spi_cs_n, spi_sck, spi_mosi, spi_miso, flash_address);
    end

    always @(negedge spi_cs_n) begin
        command = 0;
        command_bits = 0;
        data_bits = 0;
    end
    always @(posedge spi_sck) if (!spi_cs_n) begin
        if (command_bits < 32) begin
            command = {command[30:0], spi_mosi};
            command_bits = command_bits + 1;
            if (command_bits == 32) begin
                if (command[31:24] !== 8'h03) $fatal(1, "Wrong SPI command");
                flash_address = command[18:0];
            end
        end else data_bits = data_bits + 1;
    end
    always @(negedge spi_sck) if (!spi_cs_n && command_bits == 32)
        spi_miso = flash[flash_address + (data_bits >> 3)][7 - (data_bits & 7)];

    initial begin
        if (!$value$plusargs("image_bytes=%d", image_bytes) ||
            image_bytes < 32 || image_bytes > 65536)
            $fatal(1, "Missing or invalid XIP image length");
        for (integer index = 0; index < 524288; index = index + 1)
            flash[index] = 8'hff;
        $readmemh("hello.xip.hex", flash, 32'h50000, 32'h50000 + image_bytes - 1);
        dut.cpu.debugTransportModuleJtagTap_1.logic_jtagLogic_rspLogic_buffer = 0;
        #1000;
        power_reset = 0;
        #1000;
        $display("JTAG_SIM_READY");
        $fflush();
        forever begin
            control = $fgetc(32'h80000000);
            if (control >= 48 && control <= 55) begin
                {tck, tms, tdi} = control - 48;
                #100;
            end else if (control == 82) begin
                $display("TDO:%0d", tdo);
                $fflush();
            end else if (control == 81 || control == -1) begin
                $finish;
            end
        end
    end
endmodule
