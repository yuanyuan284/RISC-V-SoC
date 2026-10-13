foreach pattern {*jtag* *svf* *chip* *watch* *download* *chain*} {
    puts "$pattern: [info commands $pattern]"
}
program_svf -help
config_chipwatcher -help
export_chipwatcher -help
download -help
program -help
svfgen -help
