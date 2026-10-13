library verilog;
use verilog.vl_types.all;
entity VexRiscv is
    port(
        externalResetVector: in     vl_logic_vector(31 downto 0);
        timerInterrupt  : in     vl_logic;
        externalInterrupt: in     vl_logic;
        softwareInterrupt: in     vl_logic;
        iBusWishbone_CYC: out    vl_logic;
        iBusWishbone_STB: out    vl_logic;
        iBusWishbone_ACK: in     vl_logic;
        iBusWishbone_WE : out    vl_logic;
        iBusWishbone_ADR: out    vl_logic_vector(29 downto 0);
        iBusWishbone_DAT_MISO: in     vl_logic_vector(31 downto 0);
        iBusWishbone_DAT_MOSI: out    vl_logic_vector(31 downto 0);
        iBusWishbone_SEL: out    vl_logic_vector(3 downto 0);
        iBusWishbone_ERR: in     vl_logic;
        iBusWishbone_BTE: out    vl_logic_vector(1 downto 0);
        iBusWishbone_CTI: out    vl_logic_vector(2 downto 0);
        dBusWishbone_CYC: out    vl_logic;
        dBusWishbone_STB: out    vl_logic;
        dBusWishbone_ACK: in     vl_logic;
        dBusWishbone_WE : out    vl_logic;
        dBusWishbone_ADR: out    vl_logic_vector(29 downto 0);
        dBusWishbone_DAT_MISO: in     vl_logic_vector(31 downto 0);
        dBusWishbone_DAT_MOSI: out    vl_logic_vector(31 downto 0);
        dBusWishbone_SEL: out    vl_logic_vector(3 downto 0);
        dBusWishbone_ERR: in     vl_logic;
        dBusWishbone_BTE: out    vl_logic_vector(1 downto 0);
        dBusWishbone_CTI: out    vl_logic_vector(2 downto 0);
        clk             : in     vl_logic;
        reset           : in     vl_logic
    );
end VexRiscv;
