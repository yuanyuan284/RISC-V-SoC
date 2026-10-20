`timescale 1ns/1ps
module tb_flash_soc;
    reg clk = 0, power_reset = 1, board_reset = 0, tck = 0;
    wire tx, tdo, spi_cs_n, spi_sck, spi_mosi;
    reg spi_miso = 1;
    reg [7:0] flash [0:524287];
    reg [31:0] command = 0;
    integer command_bits = 0, data_bits = 0, transactions = 0;
    reg [18:0] flash_address = 0;
    reg [7:0] sampled;
    reg [7:0] received [0:63];
    integer count = 0;
    localparam integer BIT_NS = 8680;

    always #20 clk = ~clk;
    always #500 tck = ~tck;
    stage3_debug_soc #(.FLASH_READ(1)) dut(.clk(clk),
        .power_reset(power_reset), .board_reset(board_reset),
        .rx(1'b1), .tx(tx), .jtag_tck(tck), .jtag_tms(1'b1),
        .jtag_tdi(1'b0), .jtag_tdo(tdo), .flash_cs_n(spi_cs_n),
        .flash_sck(spi_sck), .flash_mosi(spi_mosi), .flash_miso(spi_miso));

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

    initial forever begin
        @(negedge tx);
        #(BIT_NS / 2);
        if (tx !== 0) $fatal(1, "Invalid UART start bit");
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            #BIT_NS;
            sampled[bit_index] = tx;
        end
        #BIT_NS;
        if (tx !== 1) $fatal(1, "Invalid UART stop bit");
        if (count == 64) $fatal(1, "Unexpected UART output");
        received[count] = sampled;
        count = count + 1;
    end

    task expect_text(input integer offset, input string expected);
        begin
            wait(count >= offset + expected.len());
            for (integer index = 0; index < expected.len(); index = index + 1)
                if (received[offset + index] !== expected[index])
                    $fatal(1, "UART byte %0d mismatch: got %h expected %h",
                           offset + index, received[offset + index], expected[index]);
        end
    endtask

    initial begin
        integer image_bytes;
        if (!$value$plusargs("image_bytes=%d", image_bytes) ||
            image_bytes < 16 || image_bytes > 65536)
            $fatal(1, "Missing or invalid XIP image length");
        $readmemh("hello.xip.hex", flash, 32'h50000, 32'h50000 + image_bytes - 1);
        #1000;
        power_reset = 0;
        expect_text(0, "BOOT FLASH\015\012HELLO,YUAN!\015\012");
        if (transactions < 40) $fatal(1, "Flash image was not fully read");
        wait(spi_cs_n);
        begin
            integer reads_after_hello;
            reg [31:0] iterations_before;
            reads_after_hello = transactions;
            iterations_before = dut.ram.ram32.memory[0];
            repeat (500) @(posedge clk);
            if (transactions !== reads_after_hello)
                $fatal(1, "Flash loop missed the instruction cache");
            if (dut.flash_read_count !== transactions)
                $fatal(1, "Flash MMIO read counter disagrees with SPI transactions");
            if (dut.ram.ram32.memory[0] <= iterations_before)
                $fatal(1, "XIP loop did not keep running in RAM");
            if (dut.ram.ram32.memory[1] !== transactions)
                $fatal(1, "CPU could not read Flash transaction count through MMIO");
        end
        $display("PASS Flash CRC and 1-way cached XIP HELLO");
        flash[32'h50010] = flash[32'h50010] ^ 8'hff;
        board_reset = 1;
        #2000;
        board_reset = 0;
        expect_text(25, "BOOT UART 64K\015\012");
        $display("PASS corrupted Flash image fails CRC and falls back to UART");
        flash[32'h50010] = flash[32'h50010] ^ 8'hff;
        flash[32'h50000] = 8'hff;
        board_reset = 1;
        #2000;
        board_reset = 0;
        expect_text(40, "BOOT UART 64K\015\012");
        $display("PASS invalid Flash header falls back to UART");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "Flash SoC boot timeout");
    end
endmodule
