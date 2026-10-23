# Verify the running unified XIP application without writing RAM or Flash.
source script/openocd/board-iotelic-ft2232h.cfg

init
set breakpoint_set 0
set halted 0
set failed [catch {
    halt
    set halted 1
    set magic [lindex [read_memory 0x30050000 32 1] 0]
    if {$magic != 0x31504958} {
        error "XIP1 header not found: $magic"
    }
    set writer [lindex [read_memory 0x4000400c 32 1] 0]
    if {($writer & 0x80) == 0} {
        error "Unified Flash writer not found: $writer"
    }

    bp 0x30050768 4 hw
    set breakpoint_set 1
    resume
    set halted 0
    wait_halt 5000
    set halted 1
    set hit_pc [dict get [get_reg -force {pc}] pc]
    if {$hit_pc != 0x30050768} {
        error "Unexpected breakpoint PC: $hit_pc"
    }
    echo "UNIFIED_HW_BREAKPOINT_PC=$hit_pc"

    rbp 0x30050768
    set breakpoint_set 0
    step
    set stepped_pc [dict get [get_reg -force {pc}] pc]
    if {$stepped_pc != 0x3005076c} {
        error "Unexpected single-step PC: $stepped_pc"
    }
    echo "UNIFIED_HW_STEP_PC=$stepped_pc"
} reason]
if {$breakpoint_set} {
    if {!$halted} {
        if {![catch {halt}]} {
            set halted 1
        }
    }
    catch {rbp 0x30050768}
}
if {$halted} {
    catch {resume}
}
if {$failed} {
    error "UNIFIED_LIVE_DEBUG_FAILED: $reason"
}
echo UNIFIED_LIVE_DEBUG_PASS
shutdown
