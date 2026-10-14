# Read-only command discovery; no device connection or programming.
foreach pattern {*bram* *ram* *memory* *jtag* *svf* *watch*} {
    puts "=== $pattern ==="
    foreach name [lsort [info commands $pattern]] {
        puts "COMMAND $name"
        if {![regexp {^(list_bram|rdbk_bram(18|20|32)?|write_bram(18|20|32)?|program_svf|svfgen|config_chipwatcher|export_chipwatcher|compile_watcher)$} $name]} {
            continue
        }
        if {[catch {$name -help} result]} {
            puts "HELP_UNAVAILABLE $result"
        } elseif {$result ne ""} {
            puts $result
        }
    }
}
