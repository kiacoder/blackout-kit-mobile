#ifndef BLACKOUT_DESCRIPTOR_GUARD_H
#define BLACKOUT_DESCRIPTOR_GUARD_H

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <unistd.h>

/* Kernel getdents64 layout; avoid allocating libc directory streams after fork. */
struct blackout_dirent64 {
    uint64_t ino;
    int64_t off;
    unsigned short reclen;
    unsigned char type;
    char name[];
};

static inline int descriptor_number(const char *name, size_t capacity) {
    int result = 0;
    for (size_t i = 0; i < capacity; ++i) {
        unsigned char c = (unsigned char)name[i];
        if (c == 0) return i == 0 ? -1 : result;
        if (c < '0' || c > '9' || result > (INT_MAX - (c - '0')) / 10) return -1;
        result = result * 10 + (c - '0');
    }
    return -1;
}

/* Older kernels and seccomp policies may reject close_range. Enumerate the
 * child's actual descriptor table instead of guessing an upper limit.
 * Called only in the single-threaded post-fork child before exec. */
static inline int close_extra_descriptors_proc(void) {
#if defined(SYS_getdents64)
    int dir = open("/proc/self/fd", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dir < 0) return -1;
    union {
        uint64_t alignment;
        char bytes[4096];
    } buffer;
    int success = 0;
    for (;;) {
        long count = syscall(SYS_getdents64, dir, buffer.bytes, sizeof(buffer.bytes));
        if (count < 0 && errno == EINTR) continue;
        if (count == 0) break;
        if (count < 0 || (size_t)count > sizeof(buffer.bytes)) {
            success = -1;
            break;
        }
        size_t pos = 0;
        while (pos < (size_t)count) {
            size_t remaining = (size_t)count - pos;
            size_t header = offsetof(struct blackout_dirent64, name);
            if (remaining <= header || pos % _Alignof(struct blackout_dirent64) != 0) {
                success = -1;
                break;
            }
            const struct blackout_dirent64 *entry =
                (const struct blackout_dirent64 *)(buffer.bytes + pos);
            size_t length = entry->reclen;
            if (length <= header || length > remaining) {
                success = -1;
                break;
            }
            int fd = descriptor_number(entry->name, length - header);
            if (fd >= 4 && fd != dir) {
                /* Linux releases the descriptor even when close returns EINTR. */
                if (syscall(SYS_close, fd) < 0 && errno != EINTR && errno != EBADF) {
                    success = -1;
                    break;
                }
            }
            pos += length;
        }
        if (success != 0) break;
    }
    if (close(dir) < 0 && errno != EINTR) return -1;
    return success;
#else
    return -1;
#endif
}

static inline int close_extra_descriptors(void) {
/* Older Android seccomp policies can trap unknown syscalls, rather than
 * return ENOSYS. Use the established /proc path across supported APIs. */
#if defined(SYS_close_range) && !defined(__ANDROID__)
    if (syscall(SYS_close_range, 4U, UINT_MAX, 0U) == 0) return 0;
#endif
    return close_extra_descriptors_proc();
}

#endif
