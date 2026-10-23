source script/openocd/board-iotelic-ft2232h.cfg
init
halt
set failed [catch {
    foreach {label address} {
        clint_mtime_high 0x0200bffc
        plic_priority 0x0c000000
        event_register 0x40002000
        flash_writer_status 0x4000400c
        xip_magic 0x30050000
    } {
        set value [lindex [read_memory $address 32 1] 0]
        echo "$label=$value"
        if {$label eq "flash_writer_status" && ($value & 0x80) == 0} {
            error "Expected the page-capable unified Flash writer"
        }
        if {$label eq "xip_magic" && $value != 0x31504958} {
            error "XIP1 header is missing"
        }
    }
} failure]
catch {resume}
if {$failed} {
    error "Unified identity probe failed: $failure"
}
echo UNIFIED_IDENTITY_OK
shutdown
