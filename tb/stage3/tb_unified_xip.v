`timescale 1ns/1ps
module tb_unified_xip #(parameter DIRECT_XIP = 0, REMOTE_JTAG = 0,
                        HELLO_IMAGE = 0, JTAG_AFTER_SELFTEST = 0);
    reg clk = 0, power_reset = 1, board_reset = 0, rx = 1;
    reg tck = 0, tms = 1, tdi = 0;
    wire tx, tdo, spi_cs_n, spi_sck, spi_mosi;
    reg spi_miso = 1;
    reg [7:0] flash [0:524287];
    reg [31:0] command = 0;
    reg [18:0] flash_address = 0;
    integer command_bits = 0, data_bits = 0, transactions = 0;
    integer timer_edges = 0, software_edges = 0, external_edges = 0;
    reg [7:0] sampled;
    reg boot_seen = 0, start_seen = 0, jtag_ready = 0;
    string line = "";
    localparam integer BIT_NS = 8680;

    initial if ($test$plusargs("PROGRESS")) forever begin
        #10000000;
        $display("UNIFIED_SIM t=%0t pc=%h spi=%0d reset=%b irq=%b spins=%0d/%0d queue=%0d switches=%0d",
                 $time, {dut.iad, 2'b00}, transactions, dut.reset,
                 {dut.external_irq, dut.software_irq, dut.timer_irq},
                 dut.ram.ram32.memory[9], dut.ram.ram32.memory[10],
                 dut.ram.ram32.memory[4], dut.ram.ram32.memory[12]);
        $fflush();
    end

    always #20 clk = ~clk;
    generate if (!REMOTE_JTAG) begin
        always #500 tck = ~tck;
    end endgenerate
    stage3_unified_soc #(.RESET_VECTOR(DIRECT_XIP ? 32'h30050010 : 32'h20000000))
        dut(.clk(clk), .power_reset(power_reset),
        .board_reset(board_reset), .rx(rx), .tx(tx),
        .jtag_tck(tck), .jtag_tms(tms), .jtag_tdi(tdi), .jtag_tdo(tdo),
        .flash_cs_n(spi_cs_n), .flash_sck(spi_sck),
        .flash_mosi(spi_mosi), .flash_miso(spi_miso));

    always @(negedge spi_cs_n) begin
        command = 0;
        command_bits = 0;
        data_bits = 0;
        transactions = transactions + 1;
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

    always @(posedge dut.timer_irq) if (!power_reset) timer_edges = timer_edges + 1;
    always @(posedge dut.software_irq) if (!power_reset) software_edges = software_edges + 1;
    always @(posedge dut.external_irq) if (!power_reset) external_edges = external_edges + 1;

    initial forever begin
        @(negedge tx); #(BIT_NS/2);
        if (tx !== 0) $fatal(1, "UART start bit invalid");
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            #BIT_NS; sampled[bit_index] = tx;
        end
        #BIT_NS;
        if (tx !== 1) $fatal(1, "UART stop bit invalid");
        $write("%c", sampled);
        if (sampled == 10) begin
            if (line == "BOOT FLASH") boot_seen = 1;
            if (HELLO_IMAGE && $test$plusargs("BAD_CRC") && line == "BOOT UART 64K") begin
                if (boot_seen || transactions == 0)
                    $fatal(1, "Corrupt Flash image was not rejected by BootROM");
                $display("PASS unified Flash BootROM rejects corrupt XIP CRC and falls back to UART");
                $finish;
            end
            if (HELLO_IMAGE && line == "HELLO,YUAN! XIP V2") begin
                if ($test$plusargs("BAD_CRC") || !boot_seen || transactions == 0)
                    $fatal(1, "Hello image did not launch through Flash BootROM");
                $display("PASS unified default reset through Flash BootROM CRC to XIP application");
                $finish;
            end
            if (!HELLO_IMAGE && line.substr(0, 13) == "FREERTOS START") begin
                if ((!DIRECT_XIP && (!boot_seen ||
                     transactions < ($test$plusargs("FAST_BOOT_CRC") ? 20 : 1000))) ||
                    (DIRECT_XIP && transactions == 0))
                    $fatal(1, "FreeRTOS did not start from the expected XIP path");
                start_seen = 1;
                if (REMOTE_JTAG && !JTAG_AFTER_SELFTEST) begin
                    $display("JTAG_SIM_READY");
                    $fflush();
                    jtag_ready = 1;
                end
                if ($test$plusargs("START_ONLY")) begin
                    if (DIRECT_XIP)
                        $display("PASS unified direct XIP RTOS startup and UART");
                    else
                        $display("PASS unified Flash BootROM, XIP RTOS startup and UART");
                    $finish;
                end
            end
            if (line.substr(0, 12) == "FREERTOS FAIL") begin
                $display("COUNTERS spins=%0d/%0d queue=%0d switches=%0d",
                         dut.ram.ram32.memory[9], dut.ram.ram32.memory[10],
                         dut.ram.ram32.memory[4], dut.ram.ram32.memory[12]);
                $fatal(1, "FreeRTOS failure: %s", line);
            end
            if (line.substr(0, 12) == "FREERTOS PASS") begin
                if (!start_seen || timer_edges < 60 || software_edges != 1 ||
                    external_edges < 2)
                    $fatal(1, "RTOS interrupt coverage missing");
                $display("PASS unified XIP FreeRTOS preemption, queue and interrupts");
                if (REMOTE_JTAG && JTAG_AFTER_SELFTEST) begin
                    $display("JTAG_SIM_READY");
                    $fflush();
                    jtag_ready = 1;
                end
                if (!REMOTE_JTAG) $finish;
            end
            line = "";
        end else if (sampled != 13) line = {line, sampled};
    end

    initial if (REMOTE_JTAG) begin
        integer command_byte;
        dut.cpu.debugTransportModuleJtagTap_1.logic_jtagLogic_rspLogic_buffer = 0;
        wait(jtag_ready);
        forever begin
            command_byte = $fgetc(32'h80000000);
            if (command_byte >= 48 && command_byte <= 55) begin
                {tck, tms, tdi} = command_byte - 48;
                #100;
            end else if (command_byte == 82) begin
                $display("TDO:%0d", tdo);
                $fflush();
            end else if (command_byte == 81 || command_byte == -1) begin
                $finish;
            end
        end
    end

    initial begin
        integer image_bytes, bit_index;
        if (!$value$plusargs("image_bytes=%d", image_bytes) ||
            image_bytes < 16 || image_bytes > 65536)
            $fatal(1, "Missing or invalid FreeRTOS XIP image length");
        if (HELLO_IMAGE)
            $readmemh("../flash/hello.xip.hex", flash,
                      32'h50000, 32'h50000 + image_bytes - 1);
        else if ($test$plusargs("FAST_BOOT_CRC")) begin
            $readmemh("freertos_xip_sim_fast_crc.hex", flash,
                      32'h50000, 32'h50000 + image_bytes - 1);
            $display("SIM_FAST_BOOT_CRC prefix_bytes=64");
            $fflush();
        end
        else
            $readmemh("freertos_xip.xip.hex", flash,
                      32'h50000, 32'h50000 + image_bytes - 1);
        if ({flash[32'h50003], flash[32'h50002],
             flash[32'h50001], flash[32'h50000]} !== 32'h31504958)
            $fatal(1, "XIP image missing or invalid at Flash offset 0x50000");
        if (HELLO_IMAGE && $test$plusargs("BAD_CRC"))
            flash[32'h50010] = flash[32'h50010] ^ 8'h01;
        #1000; power_reset = 0;
        if (!HELLO_IMAGE && !$test$plusargs("START_ONLY") &&
            (!REMOTE_JTAG || JTAG_AFTER_SELFTEST)) begin
            wait(start_seen); #3000000;
            rx = 0; #BIT_NS;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                rx = (8'h52 >> bit_index) & 1; #BIT_NS;
            end
            rx = 1; #BIT_NS;
        end
    end
    initial begin
        #(HELLO_IMAGE ? 200000000 : DIRECT_XIP ? 1500000000 : 2000000000);
        $display("PC=%h SPI=%0d timer=%0d software=%0d external=%0d",
                 {dut.iad, 2'b00}, transactions, timer_edges,
                 software_edges, external_edges);
        $fatal(1, "Unified XIP simulation timeout");
    end
endmodule
