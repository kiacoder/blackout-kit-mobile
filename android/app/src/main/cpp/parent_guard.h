#ifndef BLACKOUT_PARENT_GUARD_H
#define BLACKOUT_PARENT_GUARD_H

#include <signal.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <unistd.h>

/* Arm before exec. Recheck after prctl to catch a parent already gone. */
static inline int arm_parent_guard(pid_t expected_parent) {
    if (prctl(PR_SET_PDEATHSIG, (unsigned long) SIGKILL, 0UL, 0UL, 0UL) != 0) {
        return -1;
    }
    return getppid() == expected_parent ? 0 : -1;
}

#endif
