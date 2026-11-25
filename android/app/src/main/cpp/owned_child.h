#ifndef BLACKOUT_OWNED_CHILD_H
#define BLACKOUT_OWNED_CHILD_H

#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/* Caller serializes every operation, including registration and reaping. */
typedef struct {
    pid_t pid;
    int token;
    int terminal_status;
} owned_child;

enum { CHILD_PENDING = -1, CHILD_UNKNOWN = 256 };

static inline int owned_child_poll(owned_child *child, int token) {
    if (token <= 0 || token != child->token) return CHILD_UNKNOWN;
    if (child->pid <= 0) return child->terminal_status;

    int status = 0;
    pid_t result;
    do {
        result = waitpid(child->pid, &status, WNOHANG);
    } while (result < 0 && errno == EINTR);
    if (result == 0) return CHILD_PENDING;
    if (result < 0 && errno != ECHILD) return CHILD_PENDING;

    child->pid = 0;
    child->terminal_status = CHILD_UNKNOWN;
    if (result > 0) {
        if (WIFEXITED(status)) child->terminal_status = WEXITSTATUS(status);
        else if (WIFSIGNALED(status)) child->terminal_status = 128 + WTERMSIG(status);
    }
    return child->terminal_status;
}

static inline int owned_child_signal(owned_child *child, int token, int sig) {
    if (sig != SIGTERM && sig != SIGKILL) return -1;
    if (owned_child_poll(child, token) != CHILD_PENDING) return -1;

    /* Verify direct-child ownership immediately before signaling, while the
       same lock excludes every launcher reaper. An exited but unreaped child
       retains its PID. Unexpected wait errors must never authorize a signal. */
    int status = 0;
    pid_t result;
    do {
        result = waitpid(child->pid, &status, WNOHANG);
    } while (result < 0 && errno == EINTR);
    if (result != 0) {
        if (result > 0 || errno == ECHILD) {
            child->pid = 0;
            child->terminal_status = CHILD_UNKNOWN;
            if (result > 0 && WIFEXITED(status)) child->terminal_status = WEXITSTATUS(status);
            else if (result > 0 && WIFSIGNALED(status)) child->terminal_status = 128 + WTERMSIG(status);
        }
        return -1;
    }
    return kill(child->pid, sig);
}

#endif
