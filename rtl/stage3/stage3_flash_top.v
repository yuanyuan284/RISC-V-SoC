// Flash XIP variant: 0x30000000..0x3007ffff maps the 512 KiB internal flash.
module stage3_flash_top(
    input wire clk_ref, i_rst, rx,
    output wire tx,
    input wire jtag_tck, jtag_tms, jtag_tdi,
    output wire jtag_tdo
);
    reg [15:0] startup = 1;
    always @(posedge clk_ref) begin
        if (!startup[15]) startup <= startup << 1;
    end
    wire clk, locked;
    sys_pll pll(.refclk(clk_ref), .reset(!startup[15]), .stdby(1'b0),
        .extlock(locked), .clk0_out(), .clk1_out(clk));
    reg [1:0] power_pipe = 3;
    reg [2:0] button_pipe = 0;
    always @(posedge clk or negedge locked) begin
        if (!locked) begin power_pipe <= 3; button_pipe <= 0; end
        else begin
            power_pipe <= {power_pipe[0], 1'b0};
            button_pipe <= {button_pipe[1:0], i_rst};
        end
    end

    wire flash_cs_n, flash_sck, flash_mosi, flash_miso;
    wire flash_io0, flash_io1, flash_io2, flash_io3;
    assign flash_io0 = flash_mosi;
    assign flash_io2 = 1'b1;
    assign flash_io3 = 1'b1;
    assign flash_miso = flash_io1;
    EF2_PHY_INTFLASH flash_pins(.mosi_io0(flash_io0), .miso_io1(flash_io1),
        .wp_n_io2(flash_io2), .hold_n_io3(flash_io3),
        .cclk(flash_sck), .cs_n(flash_cs_n));

    stage3_debug_soc #(.FLASH_READ(1)) soc(.clk(clk),
        .power_reset(power_pipe[1]), .board_reset(button_pipe[2]),
        .rx(rx), .tx(tx), .jtag_tck(jtag_tck), .jtag_tms(jtag_tms),
        .jtag_tdi(jtag_tdi), .jtag_tdo(jtag_tdo),
        .flash_cs_n(flash_cs_n), .flash_sck(flash_sck),
        .flash_mosi(flash_mosi), .flash_miso(flash_miso));
endmodule
