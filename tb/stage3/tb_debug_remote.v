`timescale 1ns/1ps
module tb_debug_remote;
    reg clk = 0, power_reset = 1;
    reg tck = 0, tms = 1, tdi = 0;
    wire tdo, tx;
    always #20 clk = ~clk;
    stage3_debug_soc dut(.clk(clk), .power_reset(power_reset),
        .board_reset(1'b0), .rx(1'b1), .tx(tx),
        .jtag_tck(tck), .jtag_tms(tms), .jtag_tdi(tdi), .jtag_tdo(tdo));
    initial if ($test$plusargs("WAVE")) begin
        $dumpfile("debug_remote.vcd");
        $dumpvars(0, power_reset, tck, tms, tdi, tdo,
                  dut.cpu.debugBus_halted, dut.cpu.debugBus_haltReq,
                  dut.cpu.decode_PC, dut.cpu.execute_PC,
                  dut.cpu.writeBack_PC, dut.cpu.decode_arbitration_isValid,
                  dut.cpu.execute_arbitration_isValid,
                  dut.cpu.writeBack_arbitration_isValid,
                  dut.cpu.debugTransportModuleJtagTap_1.tap_fsm_state,
                  dut.cpu.debugTransportModuleJtagTap_1.tap_instruction,
                  dut.cycle, dut.strobe, dut.address, dut.write_enable,
                  dut.write_data, dut.read_data, dut.ack,
                  dut.ram_select);
    end
    integer command;
    initial begin
        // DMI data before the first response is unspecified. Choose a legal
        // power-up value for this latch only; unknown later responses still fail.
        dut.cpu.debugTransportModuleJtagTap_1.logic_jtagLogic_rspLogic_buffer = 0;
        #1000;
        power_reset = 0;
        #1000;
        $display("JTAG_SIM_READY");
        $fflush();
        forever begin
            command = $fgetc(32'h80000000);
            if (command >= 48 && command <= 55) begin
                {tck, tms, tdi} = command - 48;
                #100;
            end else if (command == 82) begin
                if (tdo !== 1'b0 && tdo !== 1'b1)
                    $display("UNKNOWN_TDO at %0t IR=%02x DMI=%011x RESPONSE=%08x", $time,
                        dut.cpu.debugTransportModuleJtagTap_1.tap_instruction,
                        dut.cpu.debugTransportModuleJtagTap_1.logic_jtagLogic_dmi_logic_store,
                        dut.cpu.debugTransportModuleJtagTap_1.logic_jtagLogic_rspLogic_buffer);
                $display("TDO:%0d", tdo);
                $fflush();
            end else if (command == 81 || command == -1) begin
                $finish;
            end
        end
    end
endmodule
