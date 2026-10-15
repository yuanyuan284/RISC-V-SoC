// Two level-sensitive sources, one machine context, priorities 0..3.
module rtos_plic(
    input wire clk, reset, cycle, strobe, write_enable,
    input wire [21:0] address,
    input wire [3:0] select,
    input wire [31:0] write_data,
    input wire [2:1] sources,
    output reg [31:0] read_data,
    output reg ack = 0,
    output wire external_irq
);
    reg [1:0] priority1 = 0, priority2 = 0, threshold = 0;
    reg [2:1] pending = 0, enabled = 0, gateway_busy = 0, claimed = 0;
    reg [1:0] winner;
    wire request = cycle && strobe && !ack && !reset;
    always @* begin
        winner = 0;
        if (pending[1] && enabled[1] && priority1 > threshold) winner = 1;
        if (pending[2] && enabled[2] && priority2 > threshold &&
            (winner == 0 || priority2 > priority1)) winner = 2;
    end
    assign external_irq = winner != 0;
    integer source;
    always @(posedge clk) begin
        if (reset) begin
            ack <= 0; read_data <= 0;
            priority1 <= 0; priority2 <= 0; threshold <= 0;
            pending <= 0; enabled <= 0; gateway_busy <= 0; claimed <= 0;
        end else begin
            ack <= request;
            for (source = 1; source <= 2; source = source + 1)
                if (sources[source] && !gateway_busy[source]) begin
                    pending[source] <= 1; gateway_busy[source] <= 1;
                end
            if (request) begin
                case (address)
                    22'h000004: read_data <= {30'b0, priority1};
                    22'h000008: read_data <= {30'b0, priority2};
                    22'h001000: read_data <= {29'b0, pending, 1'b0};
                    22'h002000: read_data <= {29'b0, enabled, 1'b0};
                    22'h200000: read_data <= {30'b0, threshold};
                    22'h200004: begin
                        read_data <= {30'b0, winner};
                        if (!write_enable && winner != 0) begin
                            pending[winner] <= 0; claimed[winner] <= 1;
                        end
                    end
                    default: read_data <= 0;
                endcase
                if (write_enable && select[0]) case (address)
                    22'h000004: priority1 <= write_data[1:0];
                    22'h000008: priority2 <= write_data[1:0];
                    22'h002000: enabled <= write_data[2:1];
                    22'h200000: threshold <= write_data[1:0];
                    22'h200004: begin
                        if (write_data == 1 && claimed[1]) begin
                            gateway_busy[1] <= 0; claimed[1] <= 0;
                        end
                        if (write_data == 2 && claimed[2]) begin
                            gateway_busy[2] <= 0; claimed[2] <= 0;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
