`timescale 1ns/1ps
module tb_rtos;
    reg clk = 0, reset = 1, rx = 1;
    wire tx;
    always #20 clk = ~clk;
    stage3_rtos_soc dut(.clk(clk), .reset(reset), .reset_vector(32'h80000000), .rx(rx), .tx(tx));
    reg [31:0] image[0:16383];
    integer i, lines = 0;
    integer timer_edges = 0, software_edges = 0, external_edges = 0;
    reg [7:0] sampled;
    string line = "";
    integer trace_file = 0;
    localparam integer BIT_NS = 8680;
    initial if ($test$plusargs("WAVE")) begin
        $dumpfile("rtos_system.vcd");
        $dumpvars(0, reset, rx, tx, lines, sampled,
                  timer_edges, software_edges, external_edges,
                  dut.timer_irq, dut.software_irq, dut.external_irq,
                  dut.clint.mtimecmp, dut.plic.pending,
                  dut.plic.claimed);
    end
    initial if ($test$plusargs("PROGRESS")) forever begin
        #10000;
        $display("RTOS_SIM_TIME %0t", $time);
        $fflush();
    end
    initial if ($test$plusargs("TRACE")) begin
        trace_file = $fopen("rtos_events.csv", "w");
        if (!trace_file) $fatal(1, "Cannot open RTOS event trace");
        $fdisplay(trace_file, "time_ps,reset,rx,tx,timer_irq,software_irq,external_irq,lines,timer_edges,software_edges,external_edges,pending,claimed");
    end
    always @(reset or rx or tx or dut.timer_irq or dut.software_irq or
             dut.external_irq or lines or timer_edges or software_edges or
             external_edges or dut.plic.pending or dut.plic.claimed)
        if (trace_file)
            $fdisplay(trace_file, "%0t,%b,%b,%b,%b,%b,%b,%0d,%0d,%0d,%0d,%b,%b",
                      $time, reset, rx, tx, dut.timer_irq,
                      dut.software_irq, dut.external_irq, lines,
                      timer_edges, software_edges, external_edges,
                      dut.plic.pending, dut.plic.claimed);
    always @(posedge dut.timer_irq) if (!reset) timer_edges = timer_edges + 1;
    always @(posedge dut.software_irq) if (!reset) software_edges = software_edges + 1;
    always @(posedge dut.external_irq) if (!reset) external_edges = external_edges + 1;
    initial forever begin
        @(negedge tx); #(BIT_NS/2);
        if (tx !== 0) $fatal(1, "UART start bit invalid");
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            #BIT_NS; sampled[bit_index] = tx;
        end
        #BIT_NS;
        if (tx !== 1) $fatal(1, "UART stop bit invalid");
        $write("%c", sampled);
        if (sampled == 10) begin
            lines = lines + 1;
            if (line.substr(0, 12) == "FREERTOS FAIL") $fatal(1, "Application assertion: %s", line);
            if (line.substr(0, 12) == "FREERTOS PASS") begin
                if (timer_edges < 60 || software_edges != 1 || external_edges < 2)
                    $fatal(1, "Interrupt paths not covered timer=%0d software=%0d external=%0d",
                        timer_edges, software_edges, external_edges);
                $display("PASS FreeRTOS real CPU tick preemption queues software and PLIC UART interrupts");
                $finish;
            end
            line = "";
        end else if (sampled != 13) line = {line, sampled};
    end
    initial begin
        #1; $readmemh("freertos.words", image);
        for (i = 0; i < 8192; i = i + 1) dut.ram.ram32.memory[i] = image[i];
        for (i = 0; i < 4096; i = i + 1) dut.ram.ram16.memory[i] = image[8192+i];
        for (i = 0; i < 2048; i = i + 1) begin
            dut.ram.ram8a.lo.memory[i] = image[12288+i][15:0];
            dut.ram.ram8a.hi.memory[i] = image[12288+i][31:16];
            dut.ram.ram8b.lo.memory[i] = image[14336+i][15:0];
            dut.ram.ram8b.hi.memory[i] = image[14336+i][31:16];
        end
        #999; reset = 0;
        wait(lines == 1); #3000000;
        // A real UART frame exercises peripheral -> PLIC -> ISR -> task.
        rx = 0; #BIT_NS;
        for (i = 0; i < 8; i = i + 1) begin rx = (8'h52 >> i) & 1; #BIT_NS; end
        rx = 1; #BIT_NS;
    end
    initial begin
        #150000000;
        $display("Ibus address=%h timer=%0d software=%0d external=%0d", {dut.iad, 2'b00},
            timer_edges, software_edges, external_edges);
        $fatal(1, "FreeRTOS simulation timeout");
    end
endmodule
