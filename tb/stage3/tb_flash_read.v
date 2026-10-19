`timescale 1ns/1ps
module tb_flash_read;
    reg clk = 0, reset = 1, cycle = 0, strobe = 0;
    reg [16:0] address = 0;
    wire [31:0] read_data;
    wire ack, spi_cs_n, spi_sck, spi_mosi;
    reg spi_miso = 1;
    reg [7:0] flash [0:524287];
    reg [31:0] command = 0;
    integer command_bits = 0, data_bits = 0, transactions = 0;
    reg [18:0] flash_address = 0;

    always #20 clk = ~clk;
    stage3_flash_read dut(.clk(clk), .reset(reset), .cycle(cycle),
        .strobe(strobe), .address(address), .read_data(read_data),
        .ack(ack), .spi_cs_n(spi_cs_n), .spi_sck(spi_sck),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso));

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
        end else begin
            data_bits = data_bits + 1;
        end
    end
    always @(negedge spi_sck) if (!spi_cs_n && command_bits == 32) begin
        spi_miso = flash[flash_address + (data_bits >> 3)][7 - (data_bits & 7)];
    end

    task read_word(input [16:0] word_address, input [31:0] expected);
        begin
            @(negedge clk);
            address = word_address;
            cycle = 1;
            strobe = 1;
            wait(ack);
            if (read_data !== expected)
                $fatal(1, "Flash word %h: got %h, expected %h", word_address,
                       read_data, expected);
            @(negedge clk);
            cycle = 0;
            strobe = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        flash[0] = 8'h12; flash[1] = 8'h34;
        flash[2] = 8'h56; flash[3] = 8'h78;
        flash[32'h40100] = 8'hde; flash[32'h40101] = 8'had;
        flash[32'h40102] = 8'hbe; flash[32'h40103] = 8'hef;
        flash[32'h7fffc] = 8'ha1; flash[32'h7fffd] = 8'hb2;
        flash[32'h7fffe] = 8'hc3; flash[32'h7ffff] = 8'hd4;
        repeat (3) @(negedge clk);
        reset = 0;
        read_word(0, 32'h78563412);
        read_word(17'h10040, 32'hefbeadde);
        read_word(17'h1ffff, 32'hd4c3b2a1);
        if (transactions !== 3) $fatal(1, "Expected three SPI reads");
        @(negedge clk);
        address = 17'h10040;
        cycle = 1;
        strobe = 1;
        wait(!spi_cs_n);
        repeat (8) @(negedge clk);
        reset = 1;
        @(negedge clk);
        if (!spi_cs_n || ack) $fatal(1, "Reset did not abort SPI read");
        cycle = 0;
        strobe = 0;
        reset = 0;
        repeat (3) @(negedge clk);
        read_word(17'h10040, 32'hefbeadde);
        $display("PASS flash read-only Wishbone SPI bridge");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Flash read timeout");
    end
endmodule
