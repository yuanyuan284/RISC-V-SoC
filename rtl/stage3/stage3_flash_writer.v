// Wishbone-mapped SPI flash programmer. Only the MCU partition is writable.
module stage3_flash_writer #(parameter [24:0] TIMEOUT_CYCLES = 25'd25000000)(
    input wire clk, reset, cycle, strobe, write_enable,
    input wire [3:0] reg_address, select,
    input wire [31:0] write_data,
    output reg [31:0] read_data = 0,
    output reg ack = 0,
    output wire busy,
    output reg spi_cs_n = 1,
    output reg spi_sck = 0,
    output reg spi_mosi = 0,
    input wire spi_miso
);
    localparam IDLE = 2'd0, SHIFT = 2'd1, GAP = 2'd2;
    localparam WREN = 2'd0, CHECK_WEL = 2'd1,
               OPERATION = 2'd2, CHECK_WIP = 2'd3;
    reg [1:0] state = IDLE, phase = WREN;
    reg [18:0] flash_address = 0;
    reg [7:0] program_data = 0, last_status = 0;
    reg [7:0] page_buffer [0:15];
    reg [4:0] page_count = 0, page_remaining = 0;
    reg [3:0] page_index = 0;
    reg page_mode = 0;
    reg [2:0] command = 0;
    reg done = 0, error = 0;
    reg [39:0] tx_shift = 0;
    reg [15:0] rx_shift = 0;
    reg [5:0] remaining = 0;
    reg [1:0] gap_count = 0;
    reg [24:0] timeout_count = 0;
    assign busy = state != IDLE;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            phase <= WREN;
            flash_address <= 0;
            program_data <= 0;
            last_status <= 0;
            command <= 0;
            page_count <= 0;
            page_remaining <= 0;
            page_index <= 0;
            page_mode <= 0;
            done <= 0;
            error <= 0;
            read_data <= 0;
            ack <= 0;
            spi_cs_n <= 1;
            spi_sck <= 0;
            spi_mosi <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            remaining <= 0;
            gap_count <= 0;
            timeout_count <= 0;
        end else begin
            ack <= 0;
            if (cycle && strobe && !ack) begin
                ack <= 1;
                case (reg_address)
                    4'h0: if (write_enable) begin
                        if (!busy && !page_mode && select == 4'hf && write_data[31:19] == 0)
                            flash_address <= write_data[18:0];
                        else begin error <= 1; page_mode <= 0; end
                    end else read_data <= {13'b0, flash_address};
                    4'h4: if (write_enable) begin
                        if (!busy && select == 4'hf && write_data[31:8] == 0 &&
                            (!page_mode || page_count < 5'd16)) begin
                            program_data <= write_data[7:0];
                            if (page_mode) begin
                                page_buffer[page_count[3:0]] <= write_data[7:0];
                                page_count <= page_count + 1'b1;
                            end
                        end else begin error <= 1; page_mode <= 0; end
                    end else read_data <= {24'b0, program_data};
                    4'h8: if (write_enable) begin
                        if (!busy && select == 4'hf && write_data == 32'd3 &&
                            flash_address[18:16] >= 3'd5) begin
                            command <= 3'd3;
                            page_mode <= 1;
                            page_count <= 0;
                            done <= 0;
                            error <= 0;
                        end else if (!busy && select == 4'hf &&
                            flash_address[18:16] >= 3'd5 &&
                            ((!page_mode && write_data[31:2] == 0 &&
                              (write_data[1:0] == 2'd1 || write_data[1:0] == 2'd2) &&
                              (write_data[1:0] != 2'd1 || flash_address[11:0] == 0)) ||
                             (page_mode && write_data == 32'd4 && page_count != 0 &&
                              {1'b0, flash_address[7:0]} + {4'b0, page_count} <= 9'd256))) begin
                            command <= write_data[2:0];
                            page_mode <= 0;
                            if (write_data == 32'd4) begin
                                page_index <= 0;
                                page_remaining <= page_count;
                            end
                            phase <= WREN;
                            state <= SHIFT;
                            tx_shift <= {8'h06, 32'b0};
                            rx_shift <= 0;
                            remaining <= 7;
                            spi_cs_n <= 0;
                            spi_sck <= 0;
                            spi_mosi <= 0;
                            timeout_count <= TIMEOUT_CYCLES;
                            last_status <= 0;
                            done <= 0;
                            error <= 0;
                        end else begin error <= 1; page_mode <= 0; end
                    end else read_data <= {29'b0, command};
                    4'hc: if (write_enable) begin
                        if (!busy && select == 4'hf && write_data[31:3] == 0) begin
                            if (write_data[1]) done <= 0;
                            if (write_data[2]) error <= 0;
                        end else error <= 1;
                    end else read_data <= {16'b0, last_status, 1'b1, 3'b0, page_mode,
                                           error, done, busy};
                    default: begin
                        read_data <= 0;
                        if (write_enable) error <= 1;
                    end
                endcase
            end

            case (state)
                SHIFT: if (!spi_sck) begin
                    spi_sck <= 1;
                    rx_shift <= {rx_shift[14:0], spi_miso};
                end else begin
                    spi_sck <= 0;
                    if (remaining == 0 && phase == OPERATION &&
                        command == 3'd4 && page_remaining != 0) begin
                        tx_shift <= {page_buffer[page_index], 32'b0};
                        spi_mosi <= page_buffer[page_index][7];
                        page_index <= page_index + 1'b1;
                        page_remaining <= page_remaining - 1'b1;
                        remaining <= 7;
                    end else if (remaining == 0) begin
                        spi_cs_n <= 1;
                        gap_count <= 2;
                        state <= GAP;
                    end else begin
                        tx_shift <= {tx_shift[38:0], 1'b0};
                        spi_mosi <= tx_shift[38];
                        remaining <= remaining - 1'b1;
                    end
                end
                GAP: if (gap_count != 0) gap_count <= gap_count - 1'b1;
                else begin
                    rx_shift <= 0;
                    spi_sck <= 0;
                    case (phase)
                        WREN: begin
                            phase <= CHECK_WEL;
                            tx_shift <= {8'h05, 32'b0};
                            remaining <= 15;
                            spi_mosi <= 0;
                            spi_cs_n <= 0;
                            state <= SHIFT;
                        end
                        CHECK_WEL: begin
                            last_status <= rx_shift[7:0];
                            if (!rx_shift[1] || rx_shift[0]) begin
                                error <= 1;
                                state <= IDLE;
                            end else begin
                                phase <= OPERATION;
                                tx_shift <= command == 3'd1 ?
                                    {8'h20, 5'b0, flash_address, 8'b0} :
                                    {8'h02, 5'b0, flash_address, program_data};
                                remaining <= command == 3'd4 ? 31 :
                                             command == 3'd1 ? 31 : 39;
                                spi_mosi <= 0;
                                spi_cs_n <= 0;
                                state <= SHIFT;
                            end
                        end
                        OPERATION: begin
                            phase <= CHECK_WIP;
                            tx_shift <= {8'h05, 32'b0};
                            remaining <= 15;
                            spi_mosi <= 0;
                            spi_cs_n <= 0;
                            state <= SHIFT;
                        end
                        CHECK_WIP: begin
                            last_status <= rx_shift[7:0];
                            if (rx_shift[0]) begin
                                tx_shift <= {8'h05, 32'b0};
                                remaining <= 15;
                                spi_mosi <= 0;
                                spi_cs_n <= 0;
                                state <= SHIFT;
                            end else begin
                                done <= 1;
                                state <= IDLE;
                            end
                        end
                    endcase
                end
            endcase

            if (busy) begin
                if (timeout_count == 0) begin
                    state <= IDLE;
                    spi_cs_n <= 1;
                    spi_sck <= 0;
                    error <= 1;
                end else timeout_count <= timeout_count - 1'b1;
            end
        end
    end
endmodule
