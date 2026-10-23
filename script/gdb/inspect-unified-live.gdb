set pagination off
set confirm off
target extended-remote 127.0.0.1:3333
monitor halt
info registers pc
info line *$pc
print tick_hooks
monitor resume
detach
quit
