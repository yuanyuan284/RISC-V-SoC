`timescale 1ns/1ps
module tb_rtos_interrupts;
    reg clk = 0, reset = 1, stop_time = 0, cycle = 0, strobe = 0, we = 0;
    reg [31:0] address = 0, data = 0;
    reg [3:0] sel = 15;
    reg [2:1] sources = 0;
    wire [31:0] cr, pr;
    wire ca, pa, ti, si, ei;
    integer count;
    reg [63:0] frozen_time;
    always #20 clk = ~clk;
    rtos_clint clint(.clk(clk), .reset(reset), .stop_time(stop_time),
        .cycle(cycle && !address[24]),
        .strobe(strobe), .write_enable(we), .address(address[15:0]),
        .select(sel), .write_data(data), .read_data(cr), .ack(ca),
        .timer_irq(ti), .software_irq(si));
    rtos_plic plic(.clk(clk), .reset(reset), .cycle(cycle && address[24]),
        .strobe(strobe), .write_enable(we), .address(address[21:0]),
        .select(sel), .write_data(data), .read_data(pr), .ack(pa),
        .sources(sources), .external_irq(ei));
    initial if ($test$plusargs("WAVE")) begin
        $dumpfile("rtos_interrupts.vcd");
        $dumpvars(0, clk, reset, stop_time, cycle, strobe, we, address, data, sel,
                  cr, ca, pr, pa, sources, ti, si, ei,
                  clint.mtime, clint.mtimecmp, clint.msip,
                  plic.priority1, plic.priority2, plic.threshold,
                  plic.pending, plic.enabled, plic.gateway_busy,
                  plic.claimed, plic.winner);
    end
    task access(input [31:0] a, input bit wr, input [31:0] d, input [3:0] mask,
                output reg [31:0] result);
        begin
            @(negedge clk); address = a; we = wr; data = d; sel = mask; cycle = 1; strobe = 1;
            count = 0;
            do begin @(posedge clk); #1; count = count + 1;
                if (count > 4) $fatal(1, "Wishbone timeout");
            end while (!(a[24] ? pa : ca));
            result = a[24] ? pr : cr;
            @(negedge clk); cycle = 0; strobe = 0;
            @(posedge clk); #1;
        end
    endtask
    task write(input [31:0] a, input [31:0] d, input [3:0] mask);
        reg [31:0] ignored;
        begin access(a, 1, d, mask, ignored); end
    endtask
    task expect_read(input [31:0] a, input [31:0] value);
        reg [31:0] result;
        begin access(a, 0, 0, 15, result);
            if (result !== value) $fatal(1, "MMIO %h expected %h got %h", a, value, result);
        end
    endtask
    initial begin
        #100; reset = 0;
        if (ti || si || ei) $fatal(1, "Unexpected interrupt after reset");
        write(0, 1, 2); if (si) $fatal(1, "MSIP ignored byte mask");
        write(0, 1, 1); if (!si) $fatal(1, "MSIP not asserted");
        write(0, 0, 1); if (si) $fatal(1, "MSIP not cleared");
        write('h4000, 'h12345678, 15); write('h4000, 'habcd0000, 12);
        expect_read('h4000, 'habcd5678);
        write('h4004, 0, 15); write('h4000, 0, 15);
        if (!ti) $fatal(1, "mtime comparison failed");
        // Safe RV32 compare update temporarily removes MTIP, then sets deadline.
        write('h4000, 'hffffffff, 15); write('h4004, 1, 15);
        if (ti) $fatal(1, "MTIP remains asserted after future deadline");
        write('hbff8, 'hfffffff0, 15); write('hbffc, 0, 15);
        repeat(30) @(posedge clk);
        expect_read('hbffc, 1);
        $display("PASS CLINT byte writes MSIP MTIP and 64-bit rollover");
        @(negedge clk); stop_time = 1; frozen_time = clint.mtime;
        repeat(5) @(posedge clk); #1;
        if (clint.mtime !== frozen_time) $fatal(1, "mtime advanced while debug stopped time");
        @(negedge clk); stop_time = 0;
        @(posedge clk); #1;
        if (clint.mtime !== frozen_time + 1'b1)
            $fatal(1, "mtime did not resume after debug stopped time");
        $display("PASS CLINT debug stop-time and resume");
        write('h01000004, 1, 15); write('h01000008, 2, 15);
        write('h01002000, 6, 15); sources = 3;
        repeat(3) @(posedge clk); #1;
        if (!ei) $fatal(1, "PLIC not pending");
        expect_read('h01200004, 2); expect_read('h01200004, 1);
        if (ei) $fatal(1, "Claim did not consume interrupt");
        // No re-delivery until complete, even with the level still high.
        expect_read('h01200004, 0);
        write('h01200004, 2, 15); repeat(3) @(posedge clk); #1;
        expect_read('h01200004, 2);
        sources = 0; write('h01200004, 2, 15); write('h01200004, 1, 15);
        write('h01200000, 2, 15); sources = 3; repeat(3) @(posedge clk); #1;
        if (ei) $fatal(1, "PLIC threshold ineffective");
        expect_read('h01200004, 0);
        write('h01200000, 0, 15); expect_read('h01200004, 2);
        sources = 0; write('h01200004, 2, 15); expect_read('h01200004, 1);
        write('h01200004, 1, 15);
        write('h01000008, 1, 15); sources = 3; repeat(3) @(posedge clk);
        expect_read('h01200004, 1); expect_read('h01200004, 2);
        $display("PASS PLIC priority tie threshold claim complete held-level gateway");
        reset = 1; @(posedge clk); #1;
        if (ei || ti || si) $fatal(1, "Interrupt state survived reset");
        $display("PASS interrupt reset"); $finish;
    end
    initial begin #100000; $fatal(1, "Peripheral test timeout"); end
endmodule
