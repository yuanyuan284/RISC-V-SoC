// Single-hart, 25 MHz mtime and SiFive-compatible machine interrupt registers.
module rtos_clint(
    input wire clk, reset, stop_time, cycle, strobe, write_enable,
    input wire [15:0] address,
    input wire [3:0] select,
    input wire [31:0] write_data,
    output reg [31:0] read_data,
    output reg ack = 0,
    output wire timer_irq, software_irq
);
    reg [63:0] mtime = 0, mtimecmp = 64'hffffffffffffffff;
    reg msip = 0;
    wire request = cycle && strobe && !ack && !reset;
    assign timer_irq = mtime >= mtimecmp;
    assign software_irq = msip;
    integer lane;
    always @(posedge clk) begin
        if (reset) begin
            ack <= 0; read_data <= 0;
            mtime <= 0; mtimecmp <= 64'hffffffffffffffff; msip <= 0;
        end else begin
            ack <= request;
            if (!stop_time) mtime <= mtime + 1'b1;
            if (request) begin
                case (address)
                    16'h0000: read_data <= {31'b0, msip};
                    16'h4000: read_data <= mtimecmp[31:0];
                    16'h4004: read_data <= mtimecmp[63:32];
                    16'hbff8: read_data <= mtime[31:0];
                    16'hbffc: read_data <= mtime[63:32];
                    default: read_data <= 0;
                endcase
                if (write_enable) begin
                    if (address == 0 && select[0]) msip <= write_data[0];
                    for (lane = 0; lane < 4; lane = lane + 1) if (select[lane]) begin
                        case (address)
                            16'h4000: mtimecmp[lane*8 +: 8] <= write_data[lane*8 +: 8];
                            16'h4004: mtimecmp[32+lane*8 +: 8] <= write_data[lane*8 +: 8];
                            16'hbff8: mtime[lane*8 +: 8] <= write_data[lane*8 +: 8];
                            16'hbffc: mtime[32+lane*8 +: 8] <= write_data[lane*8 +: 8];
                            default: ;
                        endcase
                    end
                end
            end
        end
    end
endmodule
