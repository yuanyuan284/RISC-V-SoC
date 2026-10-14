module watch_probe_top(
    input wire clk_ref,
    input wire i_rst,
    input wire rx,
    output wire tx
);
    reg [23:0] count = 0;
    always @(posedge clk_ref) begin
        if (i_rst) count <= 0;
        else count <= count + 1'b1;
    end
    assign tx = count[23] ^ rx;
endmodule
