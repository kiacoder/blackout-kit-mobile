#define _GNU_SOURCE
#include "parent_guard.h"
#include "owned_child.h"
#include "descriptor_guard.h"
#include <assert.h>
#include <errno.h>
#include <sys/wait.h>

static void test_parent_exit(void) {
    int ready[2];
    assert(pipe(ready) == 0);
    pid_t parent = fork();
    assert(parent >= 0);
    if (parent == 0) {
        close(ready[0]);
        pid_t expected = getpid();
        pid_t child = fork();
        if (child < 0) _exit(1);
        if (child == 0) {
            if (arm_parent_guard(expected) != 0) _exit(2);
            pid_t self = getpid();
            if (write(ready[1], &self, sizeof(self)) != (ssize_t)sizeof(self)) _exit(3);
            for (;;) pause();
        }
        /* Wait for child to arm before exiting. */
        int status = 0;
        while (waitpid(child, &status, WNOHANG) == 0) {
            /* Parent is terminated by the test controller. */
            pause();
        }
        _exit(4);
    }
    close(ready[1]);
    pid_t guarded_child;
    assert(read(ready[0], &guarded_child, sizeof(guarded_child)) == (ssize_t)sizeof(guarded_child));
    close(ready[0]);
    assert(kill(parent, SIGKILL) == 0);
    int status;
    assert(waitpid(parent, &status, 0) == parent);
    assert(WIFSIGNALED(status));
    /* Subreaper receives the orphaned child. */
    pid_t child = waitpid(guarded_child, &status, 0);
    assert(child == guarded_child && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
}

static void test_owned_child(void) {
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        for (;;) pause();
    }
    owned_child owner = {child, 42, CHILD_UNKNOWN};
    assert(owned_child_poll(&owner, 41) == CHILD_UNKNOWN);
    assert(owned_child_signal(&owner, 41, SIGKILL) == -1);
    assert(owned_child_signal(&owner, 42, SIGUSR1) == -1);
    assert(owned_child_poll(&owner, 42) == CHILD_PENDING);
    assert(owned_child_signal(&owner, 42, SIGTERM) == 0);
    int status;
    do {
        status = owned_child_poll(&owner, 42);
        if (status == CHILD_PENDING) usleep(1000);
    } while (status == CHILD_PENDING);
    assert(status == 128 + SIGTERM);
    assert(owned_child_poll(&owner, 42) == status);
    assert(owned_child_signal(&owner, 42, SIGKILL) == -1);

    /* A foreign PID cannot be authorized, even with the current token. */
    owner = (owned_child){getpid(), 43, CHILD_UNKNOWN};
    assert(owned_child_signal(&owner, 43, SIGKILL) == -1);
    assert(owned_child_poll(&owner, 43) == CHILD_UNKNOWN);
    assert(owned_child_poll(&owner, 42) == CHILD_UNKNOWN);
}

static void test_descriptor_cleanup(int (*cleanup)(void)) {
    int base = open("/dev/null", O_RDONLY);
    assert(base >= 0);
    int high = fcntl(base, F_DUPFD, 256);
    int higher = fcntl(base, F_DUPFD, 512);
    assert(high >= 256 && higher >= 512);
    /* Exercise more than one getdents64 buffer, including sparse high FDs. */
    int many[256];
    for (size_t i = 0; i < sizeof(many) / sizeof(many[0]); ++i) {
        many[i] = fcntl(base, F_DUPFD, 600);
        assert(many[i] >= 600);
    }
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (dup2(base, 3) < 0) _exit(1);
        if (cleanup() != 0) _exit(2);
        if (fcntl(3, F_GETFD) < 0) _exit(3);
        if (fcntl(high, F_GETFD) >= 0 || errno != EBADF) _exit(4);
        if (fcntl(higher, F_GETFD) >= 0 || errno != EBADF) _exit(5);
        for (size_t i = 0; i < sizeof(many) / sizeof(many[0]); ++i) {
            if (fcntl(many[i], F_GETFD) >= 0 || errno != EBADF) _exit(6);
        }
        _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(fcntl(high, F_GETFD) >= 0 && fcntl(higher, F_GETFD) >= 0);
    for (size_t i = 0; i < sizeof(many) / sizeof(many[0]); ++i) {
        assert(fcntl(many[i], F_GETFD) >= 0);
        close(many[i]);
    }
    close(high);
    close(higher);
    close(base);
}

int main(void) {
    alarm(10);
    assert(prctl(PR_SET_CHILD_SUBREAPER, 1UL, 0UL, 0UL, 0UL) == 0);
    assert(arm_parent_guard(-1) == -1);
    assert(prctl(PR_SET_PDEATHSIG, 0UL, 0UL, 0UL, 0UL) == 0);
    test_parent_exit();
    test_owned_child();
    test_descriptor_cleanup(close_extra_descriptors);
    test_descriptor_cleanup(close_extra_descriptors_proc);
    return 0;
}
