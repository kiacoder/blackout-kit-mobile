/* Synthetic device acceptance child; never packaged for distribution. */
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "exit23") == 0) return 23;
    if (argc != 3 || strcmp(argv[1], "hold") != 0) return 125;
    alarm(30); /* Bound a failed acceptance run independently of the owner. */
    int fd = open(argv[2], O_RDWR | O_CLOEXEC);
    if (fd < 0) return 125;
    struct flock lock = {0};
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    if (fcntl(fd, F_SETLK, &lock) != 0) return 125;
    /* Record readiness only after owning the lock. */
    if (write(fd, "R", 1) != 1) return 125;
    for (;;) pause();
}
