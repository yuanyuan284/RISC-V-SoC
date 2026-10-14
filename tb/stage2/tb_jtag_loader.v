`timescale 1ns/1ps

module tb_jtag_loader;
    reg clk = 0, tck = 0, reset = 1;
    reg shift = 0, update = 0, tdi = 0;
    wire tdo, cyc, stb, we, boot_ram, hold_reset, ack;
    wire [31:0] address, write_data, read_data;
    wire [3:0] select;
    reg [68:0] response;

    always #20 clk = ~clk;
    always #100 tck = ~tck;

    jtag_wb_loader loader(
        .i_clk(clk), .i_reset(reset), .i_jtag_tck(tck),
        .i_jtag_shift(shift), .i_jtag_update(update), .i_jtag_tdi(tdi),
        .o_jtag_tdo(tdo), .o_wb_cyc(cyc), .o_wb_stb(stb),
        .o_wb_we(we), .o_wb_adr(address), .o_wb_dat(write_data),
        .o_wb_sel(select), .i_wb_dat(read_data), .i_wb_ack(ack),
        .o_boot_from_ram(boot_ram), .o_hold_reset(hold_reset)
    );
    stage2_memory ram(
        .clk(clk), .reset(reset), .address(address),
        .write_data(write_data), .select(select), .write_enable(we),
        .cycle(cyc), .strobe(stb), .read_data(read_data), .ack(ack)
    );

    function [68:0] command(input bit write_enable,
                             input [31:0] addr, input [31:0] data);
        command = {data, addr, 4'hf, write_enable};
    endfunction

    task scan(input [68:0] frame, output [68:0] result);
        integer bit_index;
        begin
            result = 0;
            for (bit_index = 0; bit_index < 69; bit_index = bit_index + 1) begin
                @(negedge tck);
                shift = 1;
                tdi = frame[bit_index];
                result[bit_index] = tdo;
            end
            @(negedge tck);
            shift = 0;
            update = 1;
            @(negedge tck);
            update = 0;
            tdi = 0;
        end
    endtask

    task transact(input [68:0] frame, input bit error_expected,
                  input [31:0] expected_data);
        reg [68:0] ignored, result;
        begin
            scan(frame, ignored);
            repeat (12) @(negedge tck);
            scan(69'b0, result);
            if (result[68:37] !== 32'h4a544147 ||
                result[34] !== 1'b1 || result[33] !== error_expected ||
                result[32] !== 1'b0 || result[31:0] !== expected_data)
                $fatal(1, "JTAG response mismatch: %018x", result);
        end
    endtask

    initial begin
        repeat (5) @(negedge tck);
        reset = 0;
        repeat (5) @(negedge tck);
        transact(command(1, 32'hffff_fffc, 2), 0, 2);
        if (hold_reset !== 1 || boot_ram !== 0)
            $fatal(1, "CPU was not held for RAM download");
        transact(command(1, 32'h80000000, 32'h12345678), 0, 32'hxxxxxxxx);
        transact(command(0, 32'h80000000, 0), 0, 32'h12345678);
        transact(command(1, 32'h80000400, 0), 1, 0);
        transact(command(1, 32'hffff_fffc, 3), 0, 3);
        if (!hold_reset || !boot_ram)
            $fatal(1, "RAM boot was not armed while CPU held");
        transact(command(1, 32'hffff_fffc, 1), 0, 1);
        if (hold_reset || !boot_ram)
            $fatal(1, "CPU was not released to RAM");
        $display("PASS: JTAG loader control, RAM write/readback, bounds, boot");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "JTAG loader simulation timeout");
    end
endmodule
