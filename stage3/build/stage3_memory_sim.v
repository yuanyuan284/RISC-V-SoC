// Two 32Kbit blocks form an 8 KiB x32 memory with independent byte writes.
module stage3_bank8k #(parameter ROM = 0)(
    input wire clk, ce, we,
    input wire [10:0] address,
    input wire [3:0] select,
    input wire [31:0] write_data,
    output wire [31:0] read_data
);
    EF2_PHY_BRAM32K #(.MODE("DP16K")) lo(
        .clka(clk), .csa(ce), .ocea(1'b1), .rsta(1'b0), .addra(address),
        .dia(write_data[15:0]), .doa(read_data[15:0]),
        .wea(we && !ROM && |select[1:0]), .bytewea(!(select[0] && select[1])),
        .bytea(select[1]), .clkb(clk), .csb(1'b0), .oceb(1'b0), .rstb(1'b0),
        .addrb(11'b0), .dib(16'b0), .web(1'b0), .byteweb(1'b0), .byteb(1'b0), .dob());
    EF2_PHY_BRAM32K #(.MODE("DP16K")) hi(
        .clka(clk), .csa(ce), .ocea(1'b1), .rsta(1'b0), .addra(address),
        .dia(write_data[31:16]), .doa(read_data[31:16]),
        .wea(we && !ROM && |select[3:2]), .bytewea(!(select[2] && select[3])),
        .bytea(select[3]), .clkb(clk), .csb(1'b0), .oceb(1'b0), .rstb(1'b0),
        .addrb(11'b0), .dib(16'b0), .web(1'b0), .byteweb(1'b0), .byteb(1'b0), .dob());
    `include "bootrom_init.vh"
endmodule

module stage3_rom(
    input wire clk, reset, cycle, strobe,
    input wire [10:0] address,
    output wire [31:0] read_data,
    output reg ack = 0
);
    wire request = cycle && strobe && !ack && !reset;
    always @(posedge clk) begin
        if (reset) ack <= 0;
        else ack <= request;
    end
    stage3_bank8k #(.ROM(1)) bank(.clk(clk), .ce(request), .we(1'b0),
        .address(address), .select(4'b0), .write_data(32'b0), .read_data(read_data));
endmodule

module stage3_ram(
    input wire clk, reset, cycle, strobe, write_enable,
    input wire [13:0] address,
    input wire [3:0] select,
    input wire [31:0] write_data,
    output wire [31:0] read_data,
    output reg ack = 0
);
    wire request = cycle && strobe && !ack && !reset;
    reg [1:0] bank_select = 0;
    wire [1:0] bank = !address[13] ? 0 : !address[12] ? 1 : !address[11] ? 2 : 3;
    always @(posedge clk) begin
        if (reset) begin ack <= 0; bank_select <= 0; end
        else begin
            ack <= request;
            if (request) bank_select <= bank;
        end
    end
    wire [31:0] data0, data1, data2, data3;
    EF2_PHY_BRAM256K #(.MODE("DP")) ram32(
        .clka(clk), .cea(request && bank == 0), .ocea(1'b1), .rsta(1'b0),
        .addra(address[12:0]), .dia(write_data), .doa(data0),
        .wea(write_enable), .weabyte(select), .clkb(clk), .ceb(1'b0),
        .oceb(1'b0), .rstb(1'b0), .addrb(13'b0), .dib(32'b0),
        .web(1'b0), .webbyte(4'b0), .dob());
    EF2_PHY_BRAM128K ram16(
        .clk(clk), .ce(request && bank == 1), .oce(1'b1), .rst(1'b0),
        .addr(address[11:0]), .di(write_data), .\do (data1),
        .we(write_enable), .webyte(select));
    stage3_bank8k ram8a(.clk(clk), .ce(request && bank == 2), .we(write_enable),
        .address(address[10:0]), .select(select), .write_data(write_data), .read_data(data2));
    stage3_bank8k ram8b(.clk(clk), .ce(request && bank == 3), .we(write_enable),
        .address(address[10:0]), .select(select), .write_data(write_data), .read_data(data3));
    assign read_data = bank_select == 0 ? data0 : bank_select == 1 ? data1 :
                       bank_select == 2 ? data2 : data3;
endmodule
