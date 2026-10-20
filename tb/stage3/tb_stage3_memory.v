`timescale 1ns/1ps
module tb_stage3_memory;
    reg clk = 0, reset = 1, cycle = 0, strobe = 0, we = 0;
    reg [13:0] address = 0;
    reg [3:0] select = 15;
    reg [31:0] write_data = 0;
    wire [31:0] data;
    wire ack;
    reg rom_cycle = 0;
    reg [10:0] rom_address = 0;
    wire [31:0] rom_data;
    wire rom_ack;
    reg [31:0] expected_rom [0:2047];
    reg [31:0] expected, got;
    integer i, bank, mask, lane;
    always #20 clk = ~clk;
    stage3_ram ram(.clk(clk), .reset(reset), .cycle(cycle), .strobe(strobe),
        .write_enable(we), .address(address), .select(select),
        .write_data(write_data), .read_data(data), .ack(ack));
    stage3_rom rom(.clk(clk), .reset(reset), .cycle(rom_cycle), .strobe(rom_cycle),
        .address(rom_address), .read_data(rom_data), .ack(rom_ack));

    initial if ($test$plusargs("WAVE")) begin
        $dumpfile("stage3_memory.vcd");
        $dumpvars(0, clk, reset, cycle, strobe, we, address, select,
                  write_data, data, ack, rom_cycle, rom_address,
                  rom_data, rom_ack, i, bank, mask);
    end

    task transaction(input integer addr, input bit wr, input [3:0] sel,
                     input [31:0] value, output [31:0] read_value);
        begin
            @(negedge clk);
            cycle = 1; strobe = 1; we = wr; select = sel;
            address = addr; write_data = value;
            @(posedge clk); #1;
            if (ack !== 1) $fatal(1, "RAM ACK missing at word %04x", addr);
            read_value = data;
            @(negedge clk); cycle = 0; strobe = 0;
            @(posedge clk); #1;
            if (ack !== 0) $fatal(1, "RAM ACK stuck");
        end
    endtask

    initial begin
        $readmemh("bootrom.words.hex", expected_rom);
        repeat (3) @(negedge clk);
        reset = 0;
        for (i = 0; i < 2048; i = i + 1) begin
            @(negedge clk); rom_address = i; rom_cycle = 1;
            @(posedge clk); #1;
            if (rom_ack !== 1 || rom_data !== expected_rom[i])
                $fatal(1, "ROM word %04x: %08x expected %08x", i, rom_data, expected_rom[i]);
            @(negedge clk); rom_cycle = 0;
            @(posedge clk); #1;
            if (rom_ack !== 0) $fatal(1, "ROM ACK stuck");
        end
        for (i = 0; i < 16384; i = i + 1)
            transaction(i, 1, 15, 32'h1357ac00 ^ i, got);
        for (i = 0; i < 16384; i = i + 1) begin
            transaction(i, 0, 15, 0, got);
            if (got !== (32'h1357ac00 ^ i))
                $fatal(1, "RAM alias/content error at %04x: %08x", i, got);
        end
        // Every byte-enable combination in all physical bank types.
        for (bank = 0; bank < 4; bank = bank + 1) begin
            i = bank == 0 ? 8191 : bank == 1 ? 12287 : bank == 2 ? 14335 : 16383;
            for (mask = 0; mask < 16; mask = mask + 1) begin
                expected = 32'h10203040;
                transaction(i, 1, 15, expected, got);
                transaction(i, 1, mask, 32'ha1b2c3d4, got);
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (mask & (1 << lane)) expected[lane*8 +: 8] = (32'ha1b2c3d4 >> (lane*8));
                transaction(i, 0, 15, 0, got);
                if (got !== expected) $fatal(1, "Bank %0d SEL %x: %08x != %08x", bank, mask, got, expected);
            end
        end
        @(negedge clk); reset = 1; cycle = 1; strobe = 1; we = 1;
        address = 16383; write_data = 0; select = 15;
        repeat (3) @(negedge clk);
        if (ack !== 0) $fatal(1, "ACK asserted during reset");
        cycle = 0; strobe = 0; reset = 0;
        transaction(16383, 0, 15, 0, got);
        if (got !== 32'ha1b2c3d4) $fatal(1, "Reset modified RAM contents");
        $display("PASS: all 8 KiB ROM / 64 KiB RAM, all byte masks, bank boundaries and reset");
        $finish;
    end
    initial begin #10000000; $fatal(1, "Memory simulation timeout"); end
endmodule
