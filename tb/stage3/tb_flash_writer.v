`timescale 1ns/1ps
module tb_flash_writer;
    reg clk = 0, reset = 1, cycle = 0, strobe = 0, write_enable = 0;
    reg [3:0] reg_address = 0, select = 4'hf;
    reg [31:0] write_data = 0;
    wire [31:0] read_data;
    wire ack, busy, spi_cs_n, spi_sck, spi_mosi;
    reg spi_miso = 1;
    reg [7:0] flash [0:524287];
    reg [7:0] opcode = 0, status_snapshot = 0;
    reg [7:0] program_bytes [0:15];
    reg [23:0] command_address = 0;
    reg write_enable_latch = 0, reject_wren = 0, stuck_wip = 0;
    integer bits_seen = 0, busy_polls = 0, transactions = 0;
    integer page_transactions = 0;

    always #20 clk = ~clk;
    stage3_flash_writer #(.TIMEOUT_CYCLES(25'd3000)) dut(
        .clk(clk), .reset(reset), .cycle(cycle),
        .strobe(strobe), .write_enable(write_enable),
        .reg_address(reg_address), .select(select), .write_data(write_data),
        .read_data(read_data), .ack(ack), .busy(busy),
        .spi_cs_n(spi_cs_n), .spi_sck(spi_sck),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso));

    always @(negedge spi_cs_n) begin
        bits_seen = 0;
        opcode = 0;
        command_address = 0;
        status_snapshot = {6'b0, write_enable_latch, busy_polls != 0};
        transactions = transactions + 1;
    end
    always @(posedge spi_sck) if (!spi_cs_n) begin
        if (bits_seen < 8) opcode = {opcode[6:0], spi_mosi};
        else if (bits_seen < 32) command_address =
            {command_address[22:0], spi_mosi};
        else if (bits_seen < 160 && opcode == 8'h02)
            program_bytes[(bits_seen - 32) >> 3] =
                {program_bytes[(bits_seen - 32) >> 3][6:0], spi_mosi};
        bits_seen = bits_seen + 1;
    end
    always @(negedge spi_sck) if (!spi_cs_n && opcode == 8'h05 &&
                                       bits_seen >= 8 && bits_seen < 16)
        spi_miso = status_snapshot[15 - bits_seen];
    always @(posedge spi_cs_n) if (!reset && bits_seen != 0) begin
        if (dut.error && bits_seen < 16) begin
            // A timeout can release CS during a partial status command.
        end else case (opcode)
            8'h06: if (!reject_wren) write_enable_latch = 1;
            8'h05: if (busy_polls != 0) busy_polls = busy_polls - 1;
            8'h20: begin
                if (!write_enable_latch || bits_seen != 32 ||
                    command_address[18:16] < 5 || command_address[11:0] != 0)
                    $fatal(1, "Unsafe or malformed sector erase");
                for (integer i = 0; i < 4096; i = i + 1)
                    flash[command_address + i] = 8'hff;
                write_enable_latch = 0;
                busy_polls = stuck_wip ? 1000 : 2;
            end
            8'h02: begin
                if (!write_enable_latch || bits_seen < 40 ||
                    bits_seen > 160 || (bits_seen & 7) != 0 ||
                    command_address[18:16] < 5 ||
                    command_address[7:0] + ((bits_seen - 32) >> 3) > 256)
                    $fatal(1, "Unsafe or malformed page program");
                for (integer i = 0; i < ((bits_seen - 32) >> 3); i = i + 1)
                    flash[command_address + i] =
                        flash[command_address + i] & program_bytes[i];
                write_enable_latch = 0;
                busy_polls = stuck_wip ? 1000 : 2;
                page_transactions = page_transactions + 1;
            end
            default: $fatal(1, "Unexpected SPI opcode %h", opcode);
        endcase
    end

    task wb_write(input [3:0] offset, input [31:0] value);
        begin
            @(negedge clk);
            reg_address = offset;
            write_data = value;
            write_enable = 1;
            cycle = 1;
            strobe = 1;
            wait(ack);
            @(negedge clk);
            cycle = 0;
            strobe = 0;
            write_enable = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    task wb_read(input [3:0] offset, output [31:0] value);
        begin
            @(negedge clk);
            reg_address = offset;
            write_enable = 0;
            cycle = 1;
            strobe = 1;
            wait(ack);
            value = read_data;
            @(negedge clk);
            cycle = 0;
            strobe = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    task await_done;
        reg [31:0] status;
        begin
            status = 0;
            while (!status[1]) begin
                wb_read(4'hc, status);
                if (status[2]) $fatal(1, "Flash controller reported error");
            end
            if (status[0] || status[15:8] != 0)
                $fatal(1, "Controller completed while Flash was busy");
        end
    endtask

    initial begin
        flash[32'h4ffff] = 8'h35;
        flash[32'h50000] = 8'hff;
        flash[32'h50001] = 8'h12;
        flash[32'h7ffff] = 8'hff;
        repeat (3) @(negedge clk);
        reset = 0;

        begin : capability
            reg [31:0] status;
            wb_read(4'hc, status);
            if (status[7] != 1 || status[3] != 0)
                $fatal(1, "Page capability/status bits missing");
        end

        wb_write(4'h0, 32'h0004f000);
        wb_write(4'h4, 32'h0000000f);
        wb_write(4'h8, 2);
        begin : denied
            reg [31:0] status;
            wb_read(4'hc, status);
            if (status[2:0] != 3'b100 || transactions != 0 ||
                flash[32'h4ffff] != 8'h35)
                $fatal(1, "Configuration partition write was not blocked");
        end

        wb_write(4'h0, 32'h00050001);
        wb_write(4'h8, 1);
        begin : unaligned
            reg [31:0] status;
            wb_read(4'hc, status);
            if (status[2:0] != 3'b100 || transactions != 0)
                $fatal(1, "Unaligned erase was not blocked");
        end

        wb_write(4'h0, 32'h00050000);
        wb_write(4'h8, 2);
        await_done();
        if (flash[32'h50000] != 8'h0f || flash[32'h50001] != 8'h12)
            $fatal(1, "Byte program changed unexpected data");
        wb_write(4'h4, 32'h000000f0);
        wb_write(4'h8, 2);
        await_done();
        if (flash[32'h50000] != 8'h00)
            $fatal(1, "Second program did not clear bits");
        wb_write(4'h8, 1);
        await_done();
        if (flash[32'h50000] != 8'hff || flash[32'h50001] != 8'hff ||
            flash[32'h4ffff] != 8'h35)
            $fatal(1, "Sector erase did not preserve configuration partition");
        wb_write(4'h0, 32'h0007ffff);
        wb_write(4'h4, 32'h0000005a);
        wb_write(4'h8, 2);
        await_done();
        if (flash[32'h7ffff] != 8'h5a)
            $fatal(1, "Last user byte was not programmed");

        wb_write(4'h0, 32'h0004f000);
        wb_write(4'h8, 3);
        begin : page_guard
            reg [31:0] status;
            wb_read(4'hc, status);
            if (!status[2] || status[3])
                $fatal(1, "Page staging entered the configuration partition");
        end

        for (integer block = 0; block < 2; block = block + 1) begin
            wb_write(4'h0, 32'h000500e0 + block * 16);
            wb_write(4'h8, 3);
            for (integer i = 0; i < 16; i = i + 1)
                wb_write(4'h4, 32'h00000080 + block * 16 + i);
            begin : staged
                reg [31:0] status;
                wb_read(4'hc, status);
                if (!status[3]) $fatal(1, "Page staging status missing");
            end
            wb_write(4'h8, 4);
            await_done();
        end
        if (page_transactions != 5)
            $fatal(1, "Expected two SPI transactions for 32 staged bytes");
        for (integer i = 0; i < 32; i = i + 1)
            if (flash[32'h500e0 + i] != (8'h80 + i))
                $fatal(1, "Page byte %0d mismatch", i);

        wb_write(4'h0, 32'h000501f8);
        wb_write(4'h8, 3);
        for (integer i = 0; i < 16; i = i + 1)
            wb_write(4'h4, i);
        wb_write(4'h8, 4);
        begin : cross_page
            reg [31:0] status;
            wb_read(4'hc, status);
            if (!status[2] || status[3] || page_transactions != 5)
                $fatal(1, "Cross-page program was not blocked");
        end

        wb_write(4'h0, 32'h0007fff0);
        wb_write(4'h8, 3);
        for (integer i = 0; i < 16; i = i + 1)
            wb_write(4'h4, i == 15 ? 32'h5a : 32'h00000020 + i);
        wb_write(4'h8, 4);
        await_done();
        for (integer i = 0; i < 16; i = i + 1)
            if (flash[32'h7fff0 + i] != (i == 15 ? 8'h5a : 8'h20 + i))
                $fatal(1, "Last Flash page byte %0d mismatch", i);

        wb_write(4'h0, 32'h00060020);
        wb_write(4'h8, 3);
        for (integer i = 0; i < 17; i = i + 1)
            wb_write(4'h4, i);
        begin : overflow
            reg [31:0] status;
            wb_read(4'hc, status);
            if (!status[2] || status[3] || page_transactions != 6)
                $fatal(1, "Page buffer overflow was not blocked");
        end

        reject_wren = 1;
        wb_write(4'h0, 32'h00060000);
        wb_write(4'h8, 1);
        wait(!busy);
        begin : no_wel
            reg [31:0] status;
            wb_read(4'hc, status);
            if (status[2:0] != 3'b100)
                $fatal(1, "Missing WEL was not rejected");
        end
        reject_wren = 0;

        stuck_wip = 1;
        wb_write(4'h8, 1);
        wait(!busy);
        begin : timed_out
            reg [31:0] status;
            wb_read(4'hc, status);
            if (status[2:0] != 3'b100 || !spi_cs_n)
                $fatal(1, "Stuck Flash operation did not time out");
        end
        $display("PASS bus-mapped SPI Flash program/erase and partition guard");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "Flash writer timeout");
    end
endmodule
