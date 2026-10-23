# Run with board-iotelic-ft2232h.cfg and -c variables described in FLASH_XIP.md.
# This uses the CPU TAP and the FPGA's MMIO SPI writer, not the EF2 config TAP.
set flash_base 0x30000000
set writer_base 0x40004000
set sector_size 4096
set user_start 0x50000
set flash_size 0x80000

foreach required {flash_image flash_offset flash_backup_prefix} {
    if {![info exists $required] || [set $required] eq ""} {
        error "Set $required before sourcing program-user-flash.tcl"
    }
}
if {![info exists flash_confirm]} { set flash_confirm "" }
if {![info exists flash_force_byte]} { set flash_force_byte 0 }
if {$flash_force_byte ni {0 1}} { error "flash_force_byte must be 0 or 1" }
if {![info exists flash_expected_before_image]} { set flash_expected_before_image "" }
if {![file isfile $flash_image]} { error "Image not found: $flash_image" }
if {![string is integer -strict $flash_offset]} {
    error "flash_offset must be an integer physical byte offset"
}
set flash_offset [expr {$flash_offset + 0}]
set input [open $flash_image rb]
set image [read $input]
close $input
set image_size [string length $image]
if {$image_size == 0 || $flash_offset < $user_start ||
    $flash_offset >= $flash_size || $image_size > $flash_size - $flash_offset} {
    error "Image must fit wholly in physical Flash 0x50000..0x7ffff"
}

set first_sector [expr {$flash_offset & ~($sector_size - 1)}]
set last_sector [expr {($flash_offset + $image_size - 1) & ~($sector_size - 1)}]
if {$flash_expected_before_image ne ""} {
    if {![file isfile $flash_expected_before_image]} {
        error "Expected-before sector not found: $flash_expected_before_image"
    }
    set expected_file [open $flash_expected_before_image rb]
    set expected_region [read $expected_file]
    close $expected_file
    set expected_size [expr {$last_sector - $first_sector + $sector_size}]
    if {[string length $expected_region] != $expected_size} {
        error "Expected-before image must contain every complete target sector"
    }
}
set sectors {}
for {set sector $first_sector} {$sector <= $last_sector} {
    incr sector $sector_size
} {
    set before_path "${flash_backup_prefix}_[format %05x $sector].before.bin"
    set after_path "${flash_backup_prefix}_[format %05x $sector].after.bin"
    if {[file exists $before_path] || [file exists $after_path]} {
        error "Backup/verification file already exists for sector [format 0x%05x $sector]"
    }
    lappend sectors [list $sector $before_path $after_path]
}

init
halt
set initial_status [lindex [read_memory [expr {$writer_base + 12}] 32 1] 0]
if {($initial_status & 9) != 0 || ($initial_status & ~0xff87) != 0} {
    error "Flash writer is busy or returned an invalid status: $initial_status"
}
set page_supported [expr {($initial_status & 0x80) != 0 && !$flash_force_byte}]

# Finish every sector backup and change plan before issuing the first write.
set plan {}
set total_changed 0
foreach item $sectors {
    lassign $item sector before_path after_path
    dump_image $before_path [expr {$flash_base + $sector}] $sector_size
    set file [open $before_path rb]
    set before [read $file]
    close $file
    if {[string length $before] != $sector_size} {
        error "Incomplete sector backup: $before_path"
    }
    if {$flash_expected_before_image ne ""} {
        set expected_begin [expr {$sector - $first_sector}]
        set expected_before [string range $expected_region $expected_begin \
            [expr {$expected_begin + $sector_size - 1}]]
        if {$before ne $expected_before} {
            error [format "Expected-before mismatch in sector 0x%05x; no write issued" $sector]
        }
    }
    set image_begin [expr {$sector - $flash_offset}]
    if {$image_begin < 0} { set image_begin 0 }
    set image_end [expr {$sector + $sector_size - 1 - $flash_offset}]
    if {$image_end >= $image_size} { set image_end [expr {$image_size - 1}] }
    set sector_begin [expr {$flash_offset + $image_begin - $sector}]
    set sector_end [expr {$flash_offset + $image_end - $sector}]
    set desired [string replace $before $sector_begin $sector_end \
        [string range $image $image_begin $image_end]]
    if {[string length $desired] != $sector_size} {
        error "Invalid sector overlay at [format 0x%05x $sector]"
    }
    set changed 0
    set erase 0
    for {set index 0} {$index < $sector_size} {incr index} {
        set old [scan [string index $before $index] %c]
        set new [scan [string index $desired $index] %c]
        if {$old != $new} {
            incr changed
            if {($new & ~$old) != 0} { set erase 1 }
        }
    }
    incr total_changed $changed
    lappend plan [list $sector $before_path $after_path $before $desired $erase $changed]
    echo [format "FLASH_PLAN sector=0x%05x changed=%d erase=%d backup=%s" \
        $sector $changed $erase $before_path]
}
if {$flash_confirm ne "PROGRAM_USER_FLASH"} {
    echo [format "FLASH_PLAN_ONLY image_bytes=%d changed_bytes=%d" \
        $image_size $total_changed]
    shutdown
}
if {$total_changed == 0} {
    echo [format "FLASH_NO_CHANGE offset=0x%05x image_bytes=%d" \
        $flash_offset $image_size]
    shutdown
}

proc flash_wait {offset} {
    global writer_base
    for {set polls 0} {$polls < 250} {incr polls} {
        set status [lindex [read_memory [expr {$writer_base + 12}] 32 1] 0]
        if {($status & 4) != 0} {
            error [format "Flash controller error at 0x%05x: status=0x%x" $offset $status]
        }
        if {($status & 1) == 0} {
            if {($status & 2) == 0} {
                error [format "Flash controller did not complete at 0x%05x" $offset]
            }
            return
        }
    }
    error [format "Flash controller poll timeout at 0x%05x" $offset]
}
proc flash_command {offset value command} {
    global writer_base
    write_memory $writer_base 32 [list $offset]
    if {$command == 2} {
        write_memory [expr {$writer_base + 4}] 32 [list $value]
    }
    write_memory [expr {$writer_base + 8}] 32 [list $command]
    flash_wait $offset
}
proc flash_page {offset bytes} {
    global writer_base
    set count [string length $bytes]
    if {$count < 1 || $count > 16 || ($offset & 255) + $count > 256} {
        error [format "Invalid page chunk at 0x%05x: %d bytes" $offset $count]
    }
    write_memory $writer_base 32 [list $offset]
    write_memory [expr {$writer_base + 8}] 32 {3}
    for {set i 0} {$i < $count} {incr i} {
        write_memory [expr {$writer_base + 4}] 32 \
            [list [scan [string index $bytes $i] %c]]
    }
    write_memory [expr {$writer_base + 8}] 32 {4}
    flash_wait $offset
}

foreach item $plan {
    lassign $item sector before_path after_path before desired erase changed
    if {$changed == 0} { continue }
    set write_started [clock milliseconds]
    if {$erase} { flash_command $sector 0 1 }
    set programmed 0
    set page_transactions 0
    if {$page_supported} {
        for {set index 0} {$index < $sector_size} {incr index 16} {
            set needed 0
            for {set byte 0} {$byte < 16} {incr byte} {
                set old [scan [string index $before [expr {$index + $byte}]] %c]
                set new [scan [string index $desired [expr {$index + $byte}]] %c]
                if {$new != 255 && ($erase || $new != $old)} { set needed 1 }
            }
            if {$needed} {
                flash_page [expr {$sector + $index}] \
                    [string range $desired $index [expr {$index + 15}]]
                incr programmed 16
                incr page_transactions
            }
        }
    } else {
        for {set index 0} {$index < $sector_size} {incr index} {
            set old [scan [string index $before $index] %c]
            set new [scan [string index $desired $index] %c]
            if {$new != 255 && ($erase || $new != $old)} {
                flash_command [expr {$sector + $index}] $new 2
                incr programmed
            }
        }
    }
    set write_ms [expr {[clock milliseconds] - $write_started}]
    dump_image $after_path [expr {$flash_base + $sector}] $sector_size
    set file [open $after_path rb]
    set actual [read $file]
    close $file
    if {$actual ne $desired} {
        error "Flash readback mismatch in sector [format 0x%05x $sector]; CPU left halted"
    }
    echo [format "FLASH_SECTOR_OK sector=0x%05x erase=%d programmed=%d pages=%d" \
        $sector $erase $programmed $page_transactions]
    echo [format "FLASH_WRITE_TIME_MS sector=0x%05x mode=%s elapsed=%d" \
        $sector [expr {$page_supported ? "page16" : "byte"}] $write_ms]
}
echo [format "FLASH_PROGRAM_OK offset=0x%05x image_bytes=%d changed_bytes=%d" \
    $flash_offset $image_size $total_changed]
# The CPU stays halted: resuming an old XIP PC after replacing its code is unsafe.
shutdown
