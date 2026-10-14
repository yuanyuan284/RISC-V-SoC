`timescale 1ns/1ps

// The functional test uses a stable 25 MHz clock in place of analog PLL lock.
module sys_pll(input wire refclk, reset, stdby,
               output wire extlock, clk0_out, clk1_out);
    reg sys_clk = 0;
    always #20 sys_clk = ~sys_clk;
    assign clk1_out = sys_clk;
    assign clk0_out = 0;
    assign extlock = !reset;
endmodule

module tb_stage2_uart;
    localparam BIT_NS = 8680;
    reg clk_ref = 0, i_rst = 0, rx = 1;
    wire tx;
    reg [7:0] frame_a [0:1023];
    reg [7:0] frame_b [0:1023];
    reg [7:0] received [0:1023];
    integer head = 0, tail = 0;
    integer i, a_length, b_length;
    reg [7:0] sampled;

    always #50 clk_ref = ~clk_ref;
    stage2_top dut(.clk_ref(clk_ref), .i_rst(i_rst), .rx(rx), .tx(tx));

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

    task send_byte(input [7:0] value);
        begin
            rx = 0;
            #BIT_NS;
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                rx = value[bit_index];
                #BIT_NS;
            end
            rx = 1;
            #BIT_NS;
        end
    endtask

    task expect_byte(input [7:0] value);
        integer wait_count;
        begin
            wait_count = 0;
            while (head == tail && wait_count < 2000) begin
                #1000;
                wait_count = wait_count + 1;
            end
            if (head == tail) $fatal(1, "Timed out waiting for UART byte %02x", value);
            if (received[head] !== value)
                $fatal(1, "UART byte %0d: got %02x expected %02x", head,
                       received[head], value);
            head = head + 1;
        end
    endtask

    task expect_text(input string text);
        begin
            for (integer index = 0; index < text.len(); index = index + 1)
                expect_byte(text[index]);
        end
    endtask

    task send_frame(input integer frame_length, input integer which);
        reg [7:0] value;
        begin
            for (integer index = 0; index < frame_length; index = index + 1) begin
                value = which == 0 ? frame_a[index] : frame_b[index];
                send_byte(value);
                expect_byte("A");
                if (index == 15) expect_byte("H");
            end
            expect_byte("G");
        end
    endtask

    initial begin
        $readmemh("app_a.frame.hex", frame_a);
        $readmemh("app_b.frame.hex", frame_b);
        a_length = 160; // 16-byte header + 144-byte aligned app A BIN
        b_length = 164; // 16-byte header + 148-byte aligned app B BIN
        expect_text("BOOT UART");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        send_frame(a_length, 0);
        expect_text("APP A: UART loaded C!");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        i_rst = 1;
        #1000;
        i_rst = 0;
        expect_text("BOOT UART");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        send_frame(b_length, 1);
        expect_text("APP B: same FPGA, new C!");
        expect_byte(8'h0d);
        expect_byte(8'h0a);
        $display("PASS: same synthesized hardware loaded and executed two C images");
        $finish;
    end

    initial begin
        #120000000;
        $fatal(1, "Overall simulation timeout");
    end
endmodule
