#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

#define REG(o) (*(volatile uint32_t *)(0x40001000u + (o)))
extern char _heap_start[], _heap_end[];

int _write(int fd, const void *buffer, size_t count) {
    if (fd != 1 && fd != 2) { errno = EBADF; return -1; }
    const unsigned char *p = buffer;
    for (size_t i = 0; i < count; ++i) {
        while (REG(0x40) & 2u) {}
        REG(0x4c) = p[i];
    }
    return (int)count;
}
void *_sbrk(ptrdiff_t increment) {
    static char *cursor;
    if (!cursor) cursor = _heap_start;
    if (increment < 0 || (uintptr_t)increment > (uintptr_t)(_heap_end - cursor)) {
        errno = ENOMEM; return (void *)-1;
    }
    char *old = cursor;
    cursor += increment;
    return old;
}
int _fstat(int fd, struct stat *st) { (void)fd; st->st_mode = S_IFCHR; return 0; }
int _isatty(int fd) { return fd == 1 || fd == 2; }
int _close(int fd) { (void)fd; errno = EBADF; return -1; }
off_t _lseek(int fd, off_t offset, int whence) {
    (void)fd; (void)offset; (void)whence; errno = ESPIPE; return -1;
}
int _read(int fd, void *buffer, size_t count) {
    (void)fd; (void)buffer; (void)count; errno = ENOSYS; return -1;
}
int _getpid(void) { return 1; }
int _kill(int pid, int signal) { (void)pid; (void)signal; errno = EINVAL; return -1; }
void _exit(int status) { (void)status; for (;;) {} }
