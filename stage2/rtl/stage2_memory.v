module stage2_memory #(
    parameter WORDS = 256,
    parameter READ_ONLY = 0,
    parameter HEX_FILE = ""
)(
    input wire clk, reset,
    input wire [31:0] address, write_data,
    input wire [3:0] select,
    input wire write_enable, cycle, strobe,
    output reg [31:0] read_data,
    output reg ack
);
    localparam AW = $clog2(WORDS);
    reg [31:0] memory [0:WORDS-1];
    wire [AW-1:0] index = address[AW+1:2];
    integer i;
    initial begin
        ack = 0;
        read_data = 0;
        if (READ_ONLY) begin
            for (i = 0; i < WORDS; i = i + 1) memory[i] = 0;
            $readmemh(HEX_FILE, memory);
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            ack <= 0;
        end else begin
            ack <= 0;
            // Classic Wishbone: gap after ACK allows the master to advance ADR.
            if (cycle && strobe && !ack) begin
                read_data <= memory[index];
                ack <= 1;
                if (!READ_ONLY && write_enable) begin
                    if (select[0]) memory[index][7:0] <= write_data[7:0];
                    if (select[1]) memory[index][15:8] <= write_data[15:8];
                    if (select[2]) memory[index][23:16] <= write_data[23:16];
                    if (select[3]) memory[index][31:24] <= write_data[31:24];
                end
            end
        end
    end
endmodule
