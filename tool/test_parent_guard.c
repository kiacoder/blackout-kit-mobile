#define _GNU_SOURCE
#include "parent_guard.h"
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

int main(void) {
    alarm(10);
    assert(prctl(PR_SET_CHILD_SUBREAPER, 1UL, 0UL, 0UL, 0UL) == 0);
    assert(arm_parent_guard(-1) == -1);
    assert(prctl(PR_SET_PDEATHSIG, 0UL, 0UL, 0UL, 0UL) == 0);
    test_parent_exit();
    return 0;
}
