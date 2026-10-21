`timescale 1ns/1ps
module tb_flash_mcu_writer;
    reg clk = 0, power_reset = 1, tck = 0;
    wire tx, tdo, spi_cs_n, spi_sck, spi_mosi;
    reg spi_miso = 1;
    reg [7:0] flash [0:524287];
    reg [7:0] opcode = 0, status_snapshot = 0;
    reg [7:0] program_bytes [0:15];
    reg [23:0] command_address = 0;
    reg write_enable_latch = 0;
    integer bits_seen = 0, busy_polls = 0;
    integer erases = 0, programs = 0;
    reg [7:0] uart_byte = 0;
    localparam integer BIT_NS = 8680;

    always #20 clk = ~clk;
    always #500 tck = ~tck;
    stage3_debug_soc #(.FLASH_READ(1), .RESET_VECTOR(32'h80000000)) dut(
        .clk(clk), .power_reset(power_reset), .board_reset(1'b0),
        .rx(1'b1), .tx(tx), .jtag_tck(tck), .jtag_tms(1'b1),
        .jtag_tdi(1'b0), .jtag_tdo(tdo),
        .flash_cs_n(spi_cs_n), .flash_sck(spi_sck),
        .flash_mosi(spi_mosi), .flash_miso(spi_miso));

    always @(negedge spi_cs_n) begin
        bits_seen = 0;
        opcode = 0;
        command_address = 0;
        status_snapshot = {6'b0, write_enable_latch, busy_polls != 0};
    end
    always @(posedge spi_sck) if (!spi_cs_n) begin
        if (bits_seen < 8) opcode = {opcode[6:0], spi_mosi};
        else if (bits_seen < 32 &&
                 (opcode == 8'h03 || opcode == 8'h20 || opcode == 8'h02))
            command_address = {command_address[22:0], spi_mosi};
        else if (bits_seen >= 32 && bits_seen < 160 && opcode == 8'h02)
            program_bytes[(bits_seen - 32) >> 3] =
                {program_bytes[(bits_seen - 32) >> 3][6:0], spi_mosi};
        bits_seen = bits_seen + 1;
    end
    always @(negedge spi_sck) if (!spi_cs_n) begin
        if (opcode == 8'h05 && bits_seen >= 8 && bits_seen < 16)
            spi_miso = status_snapshot[15 - bits_seen];
        else if (opcode == 8'h03 && bits_seen >= 32 && bits_seen < 64)
            spi_miso = flash[command_address + ((bits_seen - 32) >> 3)]
                            [7 - ((bits_seen - 32) & 7)];
    end
    always @(posedge spi_cs_n) if (!power_reset && bits_seen != 0) begin
        case (opcode)
            8'h03: if (bits_seen != 64) $fatal(1, "Malformed Flash read");
            8'h06: write_enable_latch = 1;
            8'h05: if (busy_polls != 0) busy_polls = busy_polls - 1;
            8'h20: begin
                if (!write_enable_latch || bits_seen != 32 ||
                    command_address != 24'h060000)
                    $fatal(1, "Unsafe Flash sector erase at %h", command_address);
                for (integer i = 0; i < 4096; i = i + 1)
                    flash[command_address + i] = 8'hff;
                write_enable_latch = 0;
                busy_polls = 2;
                erases = erases + 1;
            end
            8'h02: begin
                if (!write_enable_latch || bits_seen < 40 ||
                    bits_seen > 160 || (bits_seen & 7) != 0 ||
                    command_address < 24'h060000 ||
                    command_address + ((bits_seen - 32) >> 3) > 24'h060004)
                    $fatal(1, "Unsafe Flash program at %h", command_address);
                for (integer i = 0; i < ((bits_seen - 32) >> 3); i = i + 1)
                    flash[command_address + i] =
                        flash[command_address + i] & program_bytes[i];
                write_enable_latch = 0;
                busy_polls = 2;
                programs = programs + 1;
            end
            default: $fatal(1, "Unexpected SPI opcode %h", opcode);
        endcase
    end

    initial begin
        for (integer i = 0; i < 524288; i = i + 1)
            flash[i] = 8'hff;
        flash[32'h4ffff] = 8'h35;
        flash[32'h60000] = 8'h00;
        flash[32'h60001] = 8'h00;
        #1;
        $readmemh("ram_writer_smoke.hex", dut.ram.ram32.memory);
        #1000;
        power_reset = 0;
    end

    initial begin
        @(negedge tx);
        #(BIT_NS / 2);
        if (tx !== 0) $fatal(1, "Invalid UART start bit");
        for (integer i = 0; i < 8; i = i + 1) begin
            #BIT_NS;
            uart_byte[i] = tx;
        end
        #BIT_NS;
        if (tx !== 1 || uart_byte !== "P")
            $fatal(1, "RAM MCU writer returned %h instead of P", uart_byte);
        if (erases != 1 || programs != 1 ||
            flash[32'h60000] != "M" || flash[32'h60001] != "C" ||
            flash[32'h60002] != "U" || flash[32'h60003] != "!" ||
            flash[32'h4ffff] != 8'h35)
            $fatal(1, "MCU Flash write or configuration protection failed");
        $display("PASS RV32 MCU RAM firmware erased, programmed and verified Flash");
        $finish;
    end
    initial begin
        #50000000;
        $fatal(1, "RAM MCU writer simulation timed out");
    end
endmodule
