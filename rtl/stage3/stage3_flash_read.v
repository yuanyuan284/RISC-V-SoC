// Read-only Wishbone bridge for the EF2 internal SPI flash (03h command).
// The CPU's one-way I-cache supplies instruction-line caching above this port.
module stage3_flash_read(
    input wire clk, reset, cycle, strobe,
    input wire [16:0] address,
    output reg [31:0] read_data = 0,
    output reg ack = 0,
    output reg spi_cs_n = 1,
    output reg spi_sck = 0,
    output reg spi_mosi = 0,
    input wire spi_miso
);
    localparam IDLE = 2'd0, SEND = 2'd1, RECEIVE = 2'd2, RESPOND = 2'd3;
    reg [1:0] state = IDLE;
    reg [5:0] remaining = 0;
    reg [31:0] tx_shift = 0;
    reg [31:0] rx_shift = 0;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            ack <= 0;
            spi_cs_n <= 1;
            spi_sck <= 0;
            spi_mosi <= 0;
            remaining <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
        end else begin
            ack <= 0;
            case (state)
                IDLE: if (cycle && strobe && !ack) begin
                    // 19-bit byte address, inside the 512 KiB device.
                    tx_shift <= {8'h03, 5'b0, address, 2'b00};
                    spi_mosi <= 1'b0;
                    spi_cs_n <= 0;
                    remaining <= 31;
                    state <= SEND;
                end
                SEND: if (!spi_sck) begin
                    spi_sck <= 1;
                end else begin
                    spi_sck <= 0;
                    if (remaining == 0) begin
                        spi_mosi <= 0;
                        remaining <= 31;
                        rx_shift <= 0;
                        state <= RECEIVE;
                    end else begin
                        tx_shift <= {tx_shift[30:0], 1'b0};
                        spi_mosi <= tx_shift[30];
                        remaining <= remaining - 1'b1;
                    end
                end
                RECEIVE: if (!spi_sck) begin
                    spi_sck <= 1;
                    rx_shift <= {rx_shift[30:0], spi_miso};
                end else begin
                    spi_sck <= 0;
                    if (remaining == 0) begin
                        spi_cs_n <= 1;
                        read_data <= {rx_shift[7:0], rx_shift[15:8],
                                      rx_shift[23:16], rx_shift[31:24]};
                        state <= RESPOND;
                    end else begin
                        remaining <= remaining - 1'b1;
                    end
                end
                RESPOND: begin
                    ack <= cycle && strobe;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
