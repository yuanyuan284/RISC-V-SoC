`timescale 1ns/1ps
module tb_debug_uart;
    reg clk = 0, power_reset = 1, board_reset = 0, tck = 0;
    wire tx, tdo;
    reg [7:0] sampled;
    reg [7:0] received [0:31];
    integer count = 0;
    localparam integer BIT_NS = 8680;
    always #20 clk = ~clk;
    always #500 tck = ~tck;
    stage3_debug_soc dut(.clk(clk), .power_reset(power_reset),
        .board_reset(board_reset), .rx(1'b1), .tx(tx),
        .jtag_tck(tck), .jtag_tms(1'b1), .jtag_tdi(1'b0), .jtag_tdo(tdo));
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
        if (count == 32) $fatal(1, "Unexpected UART output");
        received[count] = sampled;
        count = count + 1;
    end
    task expect_banner(input integer offset);
        string banner;
        begin
            banner = "BOOT UART 64K\015\012";
            wait(count >= offset + banner.len());
            for (integer index = 0; index < banner.len(); index = index + 1)
                if (received[offset + index] !== banner[index])
                    $fatal(1, "Boot banner byte %0d mismatch", index);
        end
    endtask
    initial begin
        #1000;
        power_reset = 0;
        expect_banner(0);
        $display("PASS debug CPU BootROM UART banner at 115200 baud");
        #BIT_NS;
        board_reset = 1;
        #2000;
        board_reset = 0;
        expect_banner(15);
        $display("PASS debug CPU board reset returns to BootROM UART");
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1, "BootROM UART timeout");
    end
endmodule
