/*
 * Experimental supervisor. The Java Process output stream is a lifetime
 * pipe, not engine input. Its EOF survives launching-thread turnover.
 * No shell, no persistent logs, no detached processes.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#include "parent_guard.h"
#include "descriptor_guard.h"

static volatile sig_atomic_t stop_requested;

static void request_stop(int signal_number) {
    (void)signal_number;
    stop_requested = 1;
}

static int status_code(int status) {
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 125;
}

static int supervise(pid_t child) {
    struct pollfd lifetime = {STDIN_FILENO, POLLIN | POLLHUP, 0};
    for (;;) {
        int status;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) return status_code(status);
        if (result < 0 && errno != EINTR) return 125;
        if (stop_requested) break;
        int ready = poll(&lifetime, 1, 100);
        if (ready < 0 && errno == EINTR) continue;
        /* The pipe must remain open and empty. Any input is a stop request. */
        if (ready != 0) break;
    }
    /* Sole reaper, no concurrent waitpid. Confirm child exit before returning. */
    if (kill(child, SIGKILL) != 0 && errno != ESRCH) return 125;
    int status;
    pid_t result;
    do {
        result = waitpid(child, &status, 0);
    } while (result < 0 && errno == EINTR);
    return result == child ? status_code(status) : 125;
}

int main(int argc, char **argv) {
    if (argc < 2 || argv[1][0] != '/') return 125;
    struct sigaction action = {0};
    action.sa_handler = request_stop;
    if (sigemptyset(&action.sa_mask) != 0 ||
        sigaction(SIGTERM, &action, NULL) != 0 ||
        sigaction(SIGINT, &action, NULL) != 0) return 125;
    /* Do not launch if the owner pipe is already closed or contains data. */
    struct pollfd lifetime = {STDIN_FILENO, POLLIN | POLLHUP, 0};
    if (poll(&lifetime, 1, 0) != 0 || stop_requested) return 125;
    pid_t parent = getpid();
    pid_t child = fork();
    if (child < 0) return 125;
    if (child == 0) {
        if (arm_parent_guard(parent) != 0) _exit(125);
        struct sigaction reset = {0};
        reset.sa_handler = SIG_DFL;
        if (sigemptyset(&reset.sa_mask) != 0 ||
            sigaction(SIGTERM, &reset, NULL) != 0 ||
            sigaction(SIGINT, &reset, NULL) != 0) _exit(125);
        int input = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (input < 0 || dup2(input, STDIN_FILENO) < 0 ||
            fcntl(STDIN_FILENO, F_SETFD, 0) < 0) _exit(125);
        if (input != STDIN_FILENO) close(input);
        close(3);
        if (close_extra_descriptors() != 0) _exit(125);
        execv(argv[1], &argv[1]);
        _exit(127);
    }
    return supervise(child);
}
