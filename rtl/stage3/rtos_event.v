// Software-triggerable external interrupt for repeatable ISR/task acceptance.
module rtos_event(
    input wire clk, reset, cycle, strobe, write_enable,
    input wire [3:0] select,
    input wire [31:0] write_data,
    output wire [31:0] read_data,
    output reg ack = 0,
    output reg irq = 0
);
    wire request = cycle && strobe && !ack && !reset;
    assign read_data = {31'b0, irq};
    always @(posedge clk) begin
        if (reset) begin ack <= 0; irq <= 0; end
        else begin
            ack <= request;
            if (request && write_enable && select[0]) irq <= write_data[0];
        end
    end
endmodule
