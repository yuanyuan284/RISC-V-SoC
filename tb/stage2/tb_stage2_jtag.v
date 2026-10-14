`timescale 1ns/1ps

module sys_pll(input wire refclk, reset, stdby,
               output wire extlock, clk0_out, clk1_out);
    reg sys_clk = 0;
    always #20 sys_clk = ~sys_clk;
    assign clk1_out = sys_clk;
    assign clk0_out = 0;
    assign extlock = !reset;
endmodule

module EF2_PHY_CONFIG #(
    parameter JTAG_PERSISTN = "DISABLE"
)(
    output wire jrstn, output wire [1:0] jrti,
    output wire jshift, jtck, jtdi, jupdate,
    output wire [1:0] jscanen, output wire jtms,
    input wire [1:0] jtdo, input wire [7:0] jtag8_ipa, jtag8_ipb,
    input wire mboot_rebootn, input wire [7:0] mboot_dynamic_addr,
    output wire dna_dout, input wire dna_clk, dna_din, dna_shift_en,
    output wire done, highz, input wire usr_gsrn, gsrn_sync_clk,
    output wire cclk, input wire cclk_en
);
    reg tb_tck = 0, tb_shift = 0, tb_update = 0, tb_tdi = 0;
    always #100 tb_tck = ~tb_tck;
    assign jrstn = 1;
    assign jrti = 0;
    assign jshift = tb_shift;
    assign jtck = tb_tck;
    assign jtdi = tb_tdi;
    assign jupdate = tb_update;
    assign jscanen = 2'b01;
    assign jtms = 0;
    assign dna_dout = 0;
    assign done = 1;
    assign highz = 0;
    assign cclk = 0;
endmodule

module tb_stage2_jtag;
    localparam BIT_NS = 8680;
    reg clk_ref = 0, i_rst = 0, rx = 1;
    wire tx;
    reg [31:0] app_words [0:35];
    reg [31:0] app_b_words [0:36];
    reg [7:0] received [0:127], sampled;
    integer head = 0, tail = 0, word_index;
    reg [68:0] ignored;
    always #50 clk_ref = ~clk_ref;
    stage2_jtag_top dut(.clk_ref(clk_ref), .i_rst(i_rst), .rx(rx), .tx(tx));

    initial begin
        forever begin
            @(negedge tx);
            #(BIT_NS / 2);
            if (tx !== 1'b0) $fatal(1, "UART start bit invalid");
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #BIT_NS;
                sampled[bit_index] = tx;
            end
            #BIT_NS;
            if (tx !== 1'b1) $fatal(1, "UART stop bit invalid");
            received[tail] = sampled;
            tail = tail + 1;
        end
    end

    task expect_byte(input [7:0] value);
        integer wait_count;
        begin
            wait_count = 0;
            while (head == tail && wait_count < 5000) begin
                #1000;
                wait_count = wait_count + 1;
            end
            if (head == tail || received[head] !== value)
                $fatal(1, "UART byte %0d: got %02x expected %02x",
                       head, received[head], value);
            head = head + 1;
        end
    endtask

    task expect_text(input string value);
        for (integer i = 0; i < value.len(); i = i + 1)
            expect_byte(value[i]);
    endtask

    function [68:0] command(input bit write_enable,
                             input [31:0] addr, input [31:0] data);
        command = {data, addr, 4'hf, write_enable};
    endfunction

    task scan(input [68:0] frame, output [68:0] result);
        begin
            result = 0;
            for (integer i = 0; i < 69; i = i + 1) begin
                @(negedge dut.core.jtag.u_config.tb_tck);
                dut.core.jtag.u_config.tb_shift = 1;
                dut.core.jtag.u_config.tb_tdi = frame[i];
                result[i] = dut.core.jtag.u_config.jtdo[0];
            end
            @(negedge dut.core.jtag.u_config.tb_tck);
            dut.core.jtag.u_config.tb_shift = 0;
            dut.core.jtag.u_config.tb_update = 1;
            @(negedge dut.core.jtag.u_config.tb_tck);
            dut.core.jtag.u_config.tb_update = 0;
            dut.core.jtag.u_config.tb_tdi = 0;
        end
    endtask

    task transact(input [68:0] frame, input bit check_data,
                  input [31:0] expected_data);
        reg [68:0] result;
        begin
            scan(frame, ignored);
            repeat (12) @(negedge dut.core.jtag.u_config.tb_tck);
            scan(69'b0, result);
            if (result[68:37] !== 32'h4a544147 ||
                result[34] !== 1'b1 || result[33:32] !== 2'b00)
                $fatal(1, "JTAG transaction failed: %018x", result);
            if (check_data && result[31:0] !== expected_data)
                $fatal(1, "RAM readback got %08x expected %08x",
                       result[31:0], expected_data);
        end
    endtask

    initial begin
        $readmemh("app_a_from_elf.hex", app_words);
        $readmemh("app_b_from_elf.hex", app_b_words);
        expect_text("BOOT UART");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        transact(command(1, 32'hffff_fffc, 2), 1, 2);
        for (word_index = 0; word_index < 36; word_index = word_index + 1)
            transact(command(1, 32'h80000000 + 4 * word_index,
                             app_words[word_index]), 0, 0);
        for (word_index = 0; word_index < 36; word_index = word_index + 1)
            transact(command(0, 32'h80000000 + 4 * word_index, 0),
                     1, app_words[word_index]);
        transact(command(1, 32'hffff_fffc, 3), 1, 3);
        transact(command(1, 32'hffff_fffc, 1), 1, 1);
        expect_text("APP A: UART loaded C!");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        transact(command(1, 32'hffff_fffc, 2), 1, 2);
        for (word_index = 0; word_index < 37; word_index = word_index + 1)
            transact(command(1, 32'h80000000 + 4 * word_index,
                             app_b_words[word_index]), 0, 0);
        for (word_index = 0; word_index < 37; word_index = word_index + 1)
            transact(command(0, 32'h80000000 + 4 * word_index, 0),
                     1, app_b_words[word_index]);
        transact(command(1, 32'hffff_fffc, 3), 1, 3);
        transact(command(1, 32'hffff_fffc, 1), 1, 1);
        expect_text("APP B: same FPGA, new C!");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        $display("PASS: same SoC executed two C ELF images loaded through JTAG bus");
        $finish;
    end

    initial begin
        #40000000;
        $fatal(1, "JTAG SoC simulation timeout");
    end
endmodule
