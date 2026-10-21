# An isolated OpenOCD Tcl backend for program-user-flash.tcl tests.
# mock_flash_path contains two sectors starting at physical 0x60000.
set input [open $mock_flash_path rb]
set mock_flash [read $input]
close $input
if {[string length $mock_flash] != 8192} { error "Expected two mock sectors" }
set mock_address 0
set mock_data 0
set mock_status [expr {[info exists mock_page_supported] && $mock_page_supported ? 0x80 : 0}]
set mock_page_mode 0
set mock_page_buffer {}
set mock_erases 0
set mock_programs 0

rename init real_init
proc init {} {}
foreach name {halt dump_image read_memory write_memory} {
    if {[llength [info commands $name]]} { rename $name real_$name }
}
proc halt {} {}
proc dump_image {path address length} {
    global mock_flash mock_corrupt_after
    set start [expr {$address - 0x30060000}]
    if {$start < 0 || $start + $length > 8192} { error "Mock dump out of range" }
    set output [open $path wb]
    set bytes [string range $mock_flash $start [expr {$start + $length - 1}]]
    if {[info exists mock_corrupt_after] && $mock_corrupt_after &&
        [string match *.after.bin $path]} {
        set bytes [string replace $bytes 0 0 [format %c 0]]
    }
    puts -nonewline $output $bytes
    close $output
}
proc read_memory {address width count} {
    global mock_status
    if {$address != 0x4000400c || $width != 32 || $count != 1} {
        error "Unexpected mock read_memory request"
    }
    return [list $mock_status]
}
proc write_memory {address width values} {
    global mock_flash mock_address mock_data mock_status mock_erases mock_programs
    global mock_page_mode mock_page_buffer mock_page_supported
    global mock_require_backup_paths
    if {[info exists mock_require_backup_paths]} {
        foreach path $mock_require_backup_paths {
            if {![file exists $path]} { error "Write attempted before every sector was backed up" }
        }
    }
    if {$width != 32 || [llength $values] != 1} { error "Invalid mock MMIO write" }
    set value [lindex $values 0]
    if {$address == 0x40004000} {
        if {$mock_page_mode} { error "Mock address changed during page staging" }
        set mock_address $value
    } elseif {$address == 0x40004004} {
        if {$mock_page_mode} {
            if {[llength $mock_page_buffer] >= 16} { error "Mock page buffer overflow" }
            lappend mock_page_buffer $value
        } else {
            set mock_data $value
        }
    } elseif {$address == 0x40004008} {
        set index [expr {$mock_address - 0x60000}]
        if {$index < 0 || $index >= 8192} { error "Mock write out of range" }
        if {$value == 1} {
            if {$mock_page_mode} { error "Mock erase during page staging" }
            if {($index & 4095) != 0} { error "Mock unaligned erase" }
            set mock_flash [string replace $mock_flash $index [expr {$index + 4095}] \
                [string repeat [format %c 255] 4096]]
            incr mock_erases
        } elseif {$value == 2} {
            if {$mock_page_mode} { error "Mock byte write during page staging" }
            set old [scan [string index $mock_flash $index] %c]
            set new [expr {$old & $mock_data}]
            set mock_flash [string replace $mock_flash $index $index [format %c $new]]
            incr mock_programs
        } elseif {$value == 3 && [info exists mock_page_supported] && $mock_page_supported} {
            set mock_page_mode 1
            set mock_page_buffer {}
            set mock_status 0x88
            return
        } elseif {$value == 4 && $mock_page_mode} {
            set count [llength $mock_page_buffer]
            if {$count < 1 || $count > 16 || ($mock_address & 255) + $count > 256} {
                error "Mock page crosses boundary or has invalid length"
            }
            for {set i 0} {$i < $count} {incr i} {
                set old [scan [string index $mock_flash [expr {$index + $i}]] %c]
                set new [expr {$old & [lindex $mock_page_buffer $i]}]
                set mock_flash [string replace $mock_flash [expr {$index + $i}] \
                    [expr {$index + $i}] [format %c $new]]
            }
            set mock_page_mode 0
            incr mock_programs
        } else {
            error "Mock unsupported Flash command"
        }
        set mock_status [expr {($mock_status & 0x80) | 2}]
    } else {
        error "Unexpected mock MMIO address"
    }
}
