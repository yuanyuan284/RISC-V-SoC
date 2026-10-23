`timescale 1ns/1ps
module sys_pll(input wire refclk, reset, stdby,
               output wire extlock, clk0_out, clk1_out);
    reg sys_clk = 0;
    always #20 sys_clk = ~sys_clk;
    assign clk1_out = sys_clk;
    assign clk0_out = 0;
    assign extlock = !reset;
endmodule

module tb_stage3_uart;
    reg clk_ref = 0, i_rst = 0, rx = 1;
    wire tx;
    integer bit_ns = 8680;
    reg fast_mode = 0;
    reg [7:0] frame [0:61455];
    reg [7:0] received [0:131071];
    integer head = 0, tail = 0, length, test_id;
    reg [7:0] sampled;
    reg ram_fetch_seen = 0;
    always #50 clk_ref = ~clk_ref;
    stage3_top dut(.clk_ref(clk_ref), .i_rst(i_rst), .rx(rx), .tx(tx));

    initial if ($test$plusargs("WAVE")) begin
        $dumpfile("stage3_uart.vcd");
        $dumpvars(0, clk_ref, i_rst, rx, tx, head, tail, sampled,
                  dut.clk, dut.reset, dut.cycle, dut.strobe,
                  dut.write_enable, dut.address, dut.write_data,
                  dut.read_data, dut.ack, dut.data_owner,
                  dut.rom_select, dut.ram_select, dut.uart_select);
    end

    initial begin
        if (!$test$plusargs("SMOKE")) begin
            // Simulation-only baud acceleration; ROM, CPU and UART RTL stay unchanged.
            fast_mode = 1;
            bit_ns = 640;
            force dut.uart.baudrate_prescaler = 15;
        end
        $display("UART simulation: bit period %0d ns, acceleration=%0d", bit_ns, fast_mode);
    end
    initial forever begin
        @(negedge tx);
        #(bit_ns / 2);
        if (tx !== 0) $fatal(1, "UART start bit invalid");
        for (integer k = 0; k < 8; k = k + 1) begin
            #bit_ns; sampled[k] = tx;
        end
        #bit_ns;
        if (tx !== 1) $fatal(1, "UART stop bit invalid");
        if (tail >= 131072) $fatal(1, "UART receive buffer overflow");
        received[tail] = sampled; tail = tail + 1;
    end
    task send_byte(input [7:0] value);
        begin
            rx = 0; #bit_ns;
            for (integer k = 0; k < 8; k = k + 1) begin rx = value[k]; #bit_ns; end
            rx = 1; #bit_ns;
        end
    endtask
    task expect_byte(input [7:0] value);
        integer waits;
        begin
            waits = 0;
            while (head == tail && waits < 100000) begin #1000; waits = waits + 1; end
            if (head == tail) $fatal(1, "UART timeout expecting %02x", value);
            if (received[head] !== value)
                $fatal(1, "UART byte %0d: got %02x expected %02x", head, received[head], value);
            head = head + 1;
        end
    endtask
    task expect_text(input string text);
        begin
            for (integer k = 0; k < text.len(); k = k + 1) expect_byte(text[k]);
        end
    endtask
    task send_header;
        begin
            for (integer k = 0; k < 16; k = k + 1) begin send_byte(frame[k]); expect_byte("A"); end
        end
    endtask
    task send_payload(input integer size);
        begin
            expect_byte("H");
            for (integer k = 16; k < size; k = k + 1) begin
                send_byte(frame[k]); expect_byte("A");
                if ((k - 15) % 4096 == 0) begin
                    $display("UART BIN received %0d bytes at %0t", k - 15, $time);
                    $fflush();
                end
            end
        end
    endtask
    task board_reset;
        begin
            i_rst = 1; #2000; i_rst = 0;
            expect_text("BOOT UART 64K\015\012");
        end
    endtask
    initial begin
        expect_text("BOOT UART 64K\015\012");
        // Oversized header must be rejected before a RAM payload is accepted.
        $readmemh("oversize.frame.hex", frame, 0, 15);
        send_header; expect_byte("E"); expect_text("BOOT UART 64K\015\012");
        if ($test$plusargs("BOUNDARY_HEADER") || $test$plusargs("BOUNDARY")) begin
            $readmemh("zero.frame.hex", frame, 0, 15);
            send_header; expect_byte("E"); expect_text("BOOT UART 64K\015\012");
            $readmemh("unaligned.frame.hex", frame, 0, 15);
            send_header; expect_byte("E"); expect_text("BOOT UART 64K\015\012");
            $readmemh("wrong_entry.frame.hex", frame, 0, 15);
            send_header; expect_byte("E"); expect_text("BOOT UART 64K\015\012");
            $readmemh("wrong_magic.frame.hex", frame, 0, 15);
            send_header; expect_byte("E"); expect_text("BOOT UART 64K\015\012");
        end
        // A corrupted CRC must return to the loader without fetching RAM instructions.
        $readmemh("badcrc.frame.hex", frame, 0, 19);
        send_header; send_payload(20); expect_byte("E"); expect_text("BOOT UART 64K\015\012");
        if ($test$plusargs("BOUNDARY_HEADER") || $test$plusargs("BOUNDARY")) begin
            $readmemh("max_header.frame.hex", frame, 0, 15);
            send_header; expect_byte("H");
            board_reset;
            $display("PASS: maximum 60 KiB header accepted; oversized header rejected");
            // The smallest valid image is one aligned instruction: jal x0, 0.
            $readmemh("min_image.frame.hex", frame, 0, 19);
            send_header; send_payload(20); expect_byte("G");
            repeat (100) @(posedge dut.clk);
            if (!ram_fetch_seen) $fatal(1, "Minimum accepted image was not fetched from RAM");
            $display("PASS: minimum 4-byte UART image accepted and fetched from RAM");
            board_reset;
        end
        if ($test$plusargs("BOUNDARY_HEADER")) begin
            $readmemh("smoke.frame.hex", frame, 0, 159);
            send_header; send_payload(160); expect_byte("G");
            expect_text("APP A: UART loaded C!\015\012");
            $display("PASS: invalid frames rejected; loader recovered and ran a valid image");
            $finish;
        end
        if ($test$plusargs("BOUNDARY")) begin
            $display("Starting maximum 60 KiB UART image");
            $fflush();
            $readmemh("max_image.frame.hex", frame, 0, 61455);
            send_header; send_payload(61456); expect_byte("G");
            expect_text("APP A: UART loaded C!\015\012");
            if (dut.ram.ram8b.lo.memory[1023] !== 16'h4445 ||
                dut.ram.ram8b.hi.memory[1023] !== 16'h4547)
                $fatal(1, "Last image word at 0x8000effc was not written");
            $display("PASS: maximum 60 KiB UART image and last RAM word");
            board_reset;
            $readmemh("smoke.frame.hex", frame, 0, 159);
            send_header; send_payload(160); expect_byte("G");
            expect_text("APP A: UART loaded C!\015\012");
            $display("PASS: reset reload after maximum UART image");
        end else if (!fast_mode) begin
            $readmemh("smoke.frame.hex", frame, 0, 159);
            send_header; send_payload(160); expect_byte("G");
            expect_text("APP A: UART loaded C!\015\012");
            $display("PASS: production baud BootROM UART download, CRC rejection and RAM execution");
        end else begin
            for (test_id = 1; test_id <= 2; test_id = test_id + 1) begin
                if (test_id == 1) begin
                    length =
                    `include "app_a.length.vh"
                    ; $readmemh("app_a.frame.hex", frame, 0, length - 1);
                end else begin
                    length =
                    `include "app_b.length.vh"
                    ; $readmemh("app_b.frame.hex", frame, 0, length - 1);
                end
                send_header; send_payload(length); expect_byte("G");
                if (test_id == 1) expect_text("APP 1: id=1 signed=-42 hex=001234ab str=form %\015\012");
                else expect_text("APP 2: id=2 signed=-42 hex=001234ab str=form %\015\012");
                expect_text("RAM=65536 ROM=8192 data=1234 bss=0 errors=0\015\012");
                expect_text("FLOAT=3.25\015\012STAGE3 PASS\015\012");
                $display("PASS: app %0d BIN via BootROM, upper RAM banks and newlib printf/snprintf/float", test_id);
                if (test_id == 1) board_reset;
            end
        end
        $finish;
    end
    // No application instruction fetch is permitted before a successful CRC ACK.
    reg launch_seen = 0;
    always @(posedge dut.clk) begin
        if (dut.reset) begin
            launch_seen <= 0;
            ram_fetch_seen <= 0;
        end
        else begin
            if (dut.uart.tx_fifo_w_stb && dut.uart.tx_fifo_w_data == "G") launch_seen <= 1;
            if (dut.ic && {dut.iad, 2'b0} >= 32'h80000000 &&
                {dut.iad, 2'b0} < 32'h80010000) begin
                if (!launch_seen) $fatal(1, "RAM instruction fetch before CRC accepted");
                ram_fetch_seen <= 1;
            end
        end
    end
    initial begin #2000000000; $fatal(1, "Overall UART simulation timeout"); end
endmodule
