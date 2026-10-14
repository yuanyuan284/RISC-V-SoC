`default_nettype wire
`timescale 1ns/1ps

// Small JTAG-style serial loader for the stage-1 SoC.
//
// This is intentionally a tiny loader, not a full RISC-V Debug Module. It uses
// the usual JTAG pins, but a simple private DR protocol:
//   shift 69 bits LSB first while the FPGA JTAG TAP is in SHIFT-DR:
//     bit  0      : write enable
//     bits 4:1    : byte select
//     bits 36:5   : byte address
//     bits 68:37  : write data
//   leave SHIFT-DR and enter UPDATE-DR to commit the command.
//
// Address 0xffff_fffc is a local control register:
//   bit 0: boot from RAM at 0x8000_0000 when reset is released
//   bit 1: hold CPU reset while JTAG downloads firmware
module jtag_wb_loader(
    input  wire        i_clk,
    input  wire        i_reset,

    input  wire        i_jtag_tck,
    input  wire        i_jtag_shift,
    input  wire        i_jtag_update,
    input  wire        i_jtag_tdi,
    output wire        o_jtag_tdo,

    output reg         o_wb_cyc,
    output reg         o_wb_stb,
    output reg         o_wb_we,
    output reg  [31:0] o_wb_adr,
    output reg  [31:0] o_wb_dat,
    output reg  [3:0]  o_wb_sel,
    input  wire [31:0] i_wb_dat,
    input  wire        i_wb_ack,

    output reg         o_boot_from_ram,
    output reg         o_hold_reset
);

    reg [68:0] shift_reg;
    reg [68:0] command_reg;
    reg [68:0] response_shift;
    reg [6:0]  shift_count;
    reg [31:0] readback_reg;
    reg [31:0] readback_tck;
    reg        response_error;
    reg        error_tck;
    reg        valid_tck;
    reg        ack_clk;
    (* async_reg = "true" *) reg ack_meta;
    (* async_reg = "true" *) reg ack_sync;
    reg        ack_seen;
    reg        commit_tck;
    reg        commit_meta;
    reg        commit_sync;
    reg        commit_seen;
    reg        pending;

    // Each clock domain samples reset locally. Initial values keep the loader
    // idle at configuration, including when TCK has not started yet.
    (* async_reg = "true" *) reg [1:0] reset_tck_sync = 2'b11;
    (* async_reg = "true" *) reg [1:0] reset_clk_sync = 2'b11;

    // Sample system reset locally even when TCK starts after configuration.
    always @(negedge i_jtag_tck) begin
        reset_tck_sync <= {reset_tck_sync[0], i_reset};
    end

    always @(posedge i_clk) begin
        reset_clk_sync <= {reset_clk_sync[0], i_reset};
    end

    wire        cmd_we   = command_reg[0];
    wire [3:0]  cmd_sel  = command_reg[4:1];
    wire [31:0] cmd_addr = command_reg[36:5];
    wire [31:0] cmd_data = command_reg[68:37];
    wire        is_ctrl  = (cmd_addr == 32'hffff_fffc);
    wire        is_ram   = (cmd_addr >= 32'h8000_0000) &&
                           (cmd_addr < 32'h8000_0400) && (cmd_addr[1:0] == 0);
    wire        busy_tck = (commit_tck != ack_sync);

    assign o_jtag_tdo = response_shift[0];

    always @(posedge i_jtag_tck) begin
        if (reset_tck_sync[1]) begin
            shift_reg <= 69'b0;
            command_reg <= 69'b0;
            response_shift <= {32'h4a544147, 37'b0};
            shift_count <= 0;
            commit_tck <= 1'b0;
            ack_meta <= 1'b0;
            ack_sync <= 1'b0;
            ack_seen <= 1'b0;
            readback_tck <= 0;
            error_tck <= 0;
            valid_tck <= 0;
        end else begin
            ack_meta <= ack_clk;
            ack_sync <= ack_meta;
            // The system-domain response is stable before its ack arrives.
            if (ack_sync != ack_seen) begin
                ack_seen <= ack_sync;
                readback_tck <= readback_reg;
                error_tck <= response_error;
                valid_tck <= 1'b1;
            end
            if (i_jtag_update) begin
                // An all-zero frame polls status without issuing a bus read.
                if (shift_count == 69 && shift_reg != 0 && !busy_tck) begin
                    command_reg <= shift_reg;
                    commit_tck <= ~commit_tck;
                    valid_tck <= 1'b0;
                end
                shift_count <= 0;
            end else if (i_jtag_shift) begin
                shift_reg <= {i_jtag_tdi, shift_reg[68:1]};
                response_shift <= {1'b0, response_shift[68:1]};
                if (shift_count < 70)
                    shift_count <= shift_count + 1'b1;
            end else begin
                // No separate CAPTURE-DR port is exposed by EF2_PHY_CONFIG.
                // Preload while idle, then freeze/shift throughout SHIFT-DR.
                response_shift <= {32'h4a544147, 1'b0, ack_sync, valid_tck,
                                   error_tck, busy_tck, readback_tck};
            end
        end
    end

    always @(posedge i_clk) begin
        if (reset_clk_sync[1]) begin
            commit_meta <= 1'b0;
            commit_sync <= 1'b0;
            commit_seen <= 1'b0;
            pending <= 1'b0;
            o_wb_cyc <= 1'b0;
            o_wb_stb <= 1'b0;
            o_wb_we <= 1'b0;
            o_wb_adr <= 32'b0;
            o_wb_dat <= 32'b0;
            o_wb_sel <= 4'b1111;
            readback_reg <= 32'b0;
            response_error <= 1'b0;
            ack_clk <= 1'b0;
            o_boot_from_ram <= 1'b0;
            o_hold_reset <= 1'b0;
        end else begin
            commit_meta <= commit_tck;
            commit_sync <= commit_meta;

            if (o_wb_cyc && i_wb_ack) begin
                o_wb_cyc <= 1'b0;
                o_wb_stb <= 1'b0;
                o_wb_we <= 1'b0;
                readback_reg <= i_wb_dat;
                pending <= 1'b0;
                ack_clk <= commit_seen;
            end

            if ((commit_sync != commit_seen) && !pending && !o_wb_cyc) begin
                commit_seen <= commit_sync;
                response_error <= 1'b0;

                if (is_ctrl) begin
                    if (cmd_we) begin
                        o_boot_from_ram <= cmd_data[0];
                        o_hold_reset <= cmd_data[1];
                    end
                    readback_reg <= cmd_we ? {30'b0, cmd_data[1:0]} :
                                            {30'b0, o_hold_reset, o_boot_from_ram};
                    ack_clk <= commit_sync;
                end else if (is_ram && o_hold_reset) begin
                    o_wb_cyc <= 1'b1;
                    o_wb_stb <= 1'b1;
                    o_wb_we <= cmd_we;
                    o_wb_adr <= cmd_addr;
                    o_wb_dat <= cmd_data;
                    o_wb_sel <= cmd_sel;
                    pending <= 1'b1;
                end else begin
                    // RAM access requires a halted CPU; reject invalid requests
                    // instead of waiting forever for a bus acknowledgement.
                    readback_reg <= 32'b0;
                    response_error <= 1'b1;
                    ack_clk <= commit_sync;
                end
            end
        end
    end

endmodule
