`default_nettype wire

module wb_ram(
    input  wire        i_clk,
    input  wire        i_reset,
    input  wire [31:0] i_wb_adr,
    input  wire [31:0] i_wb_dat,
    input  wire  [3:0] i_wb_sel,
    input  wire        i_wb_we,
    input  wire        i_wb_cyc,
    input  wire        i_wb_stb,
    output reg  [31:0] o_wb_dat,
    output reg         o_wb_ack
);

parameter SIZE = 512;
parameter INITIAL_HEX = "";

// Force the inferred memory toward FPGA Block RAM.
// This is especially important for the ROM, otherwise the ROM can consume
// a very large number of LUTs.
reg [31:0] data [0:SIZE-1] /* synthesis syn_ramstyle="block_ram" */;

initial begin
    if (INITIAL_HEX != "")
        $readmemh(INITIAL_HEX, data);
end

localparam addr_width = $clog2(SIZE);
wire [addr_width-1:0] data_addr = i_wb_adr[addr_width+1:2];

always @(posedge i_clk) begin
    if (i_reset) begin
        o_wb_ack <= 1'b0;
        o_wb_dat <= 32'b0;
    end else begin
        o_wb_ack <= 1'b0;

        if (i_wb_cyc && i_wb_stb) begin
            o_wb_ack <= 1'b1;
            o_wb_dat <= data[data_addr];

            if (i_wb_we) begin
                if (i_wb_sel[0])
                    data[data_addr][7:0]   <= i_wb_dat[7:0];
                if (i_wb_sel[1])
                    data[data_addr][15:8]  <= i_wb_dat[15:8];
                if (i_wb_sel[2])
                    data[data_addr][23:16] <= i_wb_dat[23:16];
                if (i_wb_sel[3])
                    data[data_addr][31:24] <= i_wb_dat[31:24];
            end
        end
    end
end

endmodule
