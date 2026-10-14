`default_nettype wire
`timescale 1ns/1ps

// Tiny RV32I bring-up core for the EF2L45LG144B.
// The supplied Stage-1 firmware only uses x5/x6 and these instructions:
//   LUI, ADDI, SW, JAL.
// Keeping only 8 registers and a tiny decoder avoids the large LUT cost of
// a generic 32-register combinational register file.
module VexRiscv (
    input  wire [31:0] externalResetVector,
    input  wire        timerInterrupt,
    input  wire        externalInterrupt,
    input  wire        softwareInterrupt,

    output reg         iBusWishbone_CYC,
    output reg         iBusWishbone_STB,
    input  wire        iBusWishbone_ACK,
    output wire        iBusWishbone_WE,
    output wire [29:0] iBusWishbone_ADR,
    input  wire [31:0] iBusWishbone_DAT_MISO,
    output wire [31:0] iBusWishbone_DAT_MOSI,
    output wire [3:0]  iBusWishbone_SEL,
    input  wire        iBusWishbone_ERR,
    output wire [1:0]  iBusWishbone_BTE,
    output wire [2:0]  iBusWishbone_CTI,

    output reg         dBusWishbone_CYC,
    output reg         dBusWishbone_STB,
    input  wire        dBusWishbone_ACK,
    output reg         dBusWishbone_WE,
    output wire [29:0] dBusWishbone_ADR,
    input  wire [31:0] dBusWishbone_DAT_MISO,
    output reg  [31:0] dBusWishbone_DAT_MOSI,
    output reg  [3:0]  dBusWishbone_SEL,
    input  wire        dBusWishbone_ERR,
    output wire [1:0]  dBusWishbone_BTE,
    output wire [2:0]  dBusWishbone_CTI,

    input  wire clk,
    input  wire reset
);

    localparam S_FETCH_REQ  = 2'd0;
    localparam S_FETCH_WAIT = 2'd1;
    localparam S_EXEC       = 2'd2;
    localparam S_STORE_WAIT = 2'd3;

    reg [1:0]  state;
    reg [31:0] pc;
    reg [31:0] instr;

    // Only x0..x7 are implemented because soc_fw.hex uses x5 and x6 only.
    reg [31:0] regs [0:7];
    reg [31:0] store_addr;
    reg [31:0] store_data;
    integer k;

    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];

    wire [31:0] rs1_data = (rs1 < 8) ? regs[rs1[2:0]] : 32'b0;
    wire [31:0] rs2_data = (rs2 < 8) ? regs[rs2[2:0]] : 32'b0;
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                          instr[20], instr[30:21], 1'b0};
    wire [31:0] rd_value = (opcode == 7'b0110111) ? {instr[31:12],12'b0} :
                           (rs1_data + imm_i);

    assign iBusWishbone_WE      = 1'b0;
    assign iBusWishbone_ADR     = pc[31:2];
    assign iBusWishbone_DAT_MOSI = 32'b0;
    assign iBusWishbone_SEL     = 4'b1111;
    assign iBusWishbone_BTE     = 2'b00;
    assign iBusWishbone_CTI     = 3'b000;

    assign dBusWishbone_ADR = store_addr[31:2];
    assign dBusWishbone_BTE = 2'b00;
    assign dBusWishbone_CTI = 3'b000;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_FETCH_REQ;
            pc <= externalResetVector;
            instr <= 32'h00000013;
            store_addr <= 32'b0;
            store_data <= 32'b0;
            iBusWishbone_CYC <= 1'b0;
            iBusWishbone_STB <= 1'b0;
            dBusWishbone_CYC <= 1'b0;
            dBusWishbone_STB <= 1'b0;
            dBusWishbone_WE <= 1'b0;
            dBusWishbone_DAT_MOSI <= 32'b0;
            dBusWishbone_SEL <= 4'b1111;
            for (k = 0; k < 8; k = k + 1)
                regs[k] <= 32'b0;
        end else begin
            regs[0] <= 32'b0;

            case (state)
                S_FETCH_REQ: begin
                    iBusWishbone_CYC <= 1'b1;
                    iBusWishbone_STB <= 1'b1;
                    state <= S_FETCH_WAIT;
                end

                S_FETCH_WAIT: begin
                    if (iBusWishbone_ACK || iBusWishbone_ERR) begin
                        iBusWishbone_CYC <= 1'b0;
                        iBusWishbone_STB <= 1'b0;
                        instr <= iBusWishbone_ACK ? iBusWishbone_DAT_MISO : 32'h00000013;
                        state <= S_EXEC;
                    end
                end

                S_EXEC: begin
                    // Sequential PC; control-flow instructions override it.
                    pc <= pc + 32'd4;

                    case (opcode)
                        7'b0110111: begin // LUI
                            if (rd < 8 && rd != 0)
                                regs[rd[2:0]] <= {instr[31:12],12'b0};
                            state <= S_FETCH_REQ;
                        end

                        7'b0010011: begin // ADDI (firmware uses rs1=x0)
                            if (funct3 == 3'b000 && rd < 8 && rd != 0)
                                regs[rd[2:0]] <= rd_value;
                            state <= S_FETCH_REQ;
                        end

                        7'b0100011: begin // SW
                            if (funct3 == 3'b010) begin
                                store_addr <= rs1_data + imm_s;
                                store_data <= rs2_data;
                                dBusWishbone_WE <= 1'b1;
                                dBusWishbone_DAT_MOSI <= rs2_data;
                                dBusWishbone_SEL <= 4'b1111;
                                dBusWishbone_CYC <= 1'b1;
                                dBusWishbone_STB <= 1'b1;
                                state <= S_STORE_WAIT;
                            end else begin
                                state <= S_FETCH_REQ;
                            end
                        end

                        7'b1101111: begin // JAL
                            if (rd < 8 && rd != 0)
                                regs[rd[2:0]] <= pc + 32'd4;
                            pc <= pc + imm_j;
                            state <= S_FETCH_REQ;
                        end

                        default: begin
                            // Unsupported instruction becomes a NOP.
                            state <= S_FETCH_REQ;
                        end
                    endcase
                end

                S_STORE_WAIT: begin
                    if (dBusWishbone_ACK || dBusWishbone_ERR) begin
                        dBusWishbone_CYC <= 1'b0;
                        dBusWishbone_STB <= 1'b0;
                        dBusWishbone_WE <= 1'b0;
                        state <= S_FETCH_REQ;
                    end
                end

                default: state <= S_FETCH_REQ;
            endcase
        end
    end

endmodule
