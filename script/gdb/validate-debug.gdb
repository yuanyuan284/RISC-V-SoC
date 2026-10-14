set pagination off
set confirm off
set remotetimeout 60
target extended-remote localhost:3333
monitor reset halt
load
compare-sections
set $pc = _start
hbreak debug_add
continue
if $pc != (unsigned int)&debug_add
  echo FAIL C breakpoint missed\n
  quit 1
end
echo PASS GDB ELF load and C breakpoint\n
set $before_pc = $pc
stepi
if $pc == $before_pc
  echo FAIL PC did not advance\n
  quit 1
end
echo PASS GDB stepi\n
delete breakpoints
hbreak debug_done
continue
if result != 9 || initialized != 7
  echo FAIL C result or data initialization mismatch\n
  quit 1
end
echo PASS C result=9 data=7\n
delete breakpoints
set $pc = _start
break debug_add
continue
if $pc != (unsigned int)&debug_add
  echo FAIL software breakpoint missed\n
  quit 1
end
echo PASS GDB software breakpoint\n
step
if result != 7
  echo FAIL C source step result mismatch\n
  quit 1
end
echo PASS GDB C source step\n
monitor halt
detach
quit
