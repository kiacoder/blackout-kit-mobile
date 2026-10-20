/*
 * fdlauncher — spawn an engine binary with a TUN file descriptor inherited.
 *
 * WHY THIS EXISTS
 * ---------------
 * Java's ProcessBuilder can only map file descriptors 0/1/2 (Redirect), and
 * the file descriptor VpnService.establish() hands back is installed through
 * Binder with FD_CLOEXEC set. A plain `ProcessBuilder(path, "-fd", N, ...)`
 * therefore gives the child a descriptor that does not exist — the engine dies
 * with EBADF the moment it touches the tunnel. That is the whole reason the
 * Xray engine works (it takes the fd in-process over JNI) while the
 * subprocess-based engines could never carry a packet.
 *
 * This helper does the part Java cannot: fork, dup2(fd, 3), execv. The caller
 * passes fd 3 on the child's command line.
 *
 * Two entry points, both reentrant and safe to call from the main thread:
 *   spawn(path, args, fd, logPath) -> child pid (or -1 on failure)
 *   poll(pid)                      -> -1 still running, >= 0 exit code
 * The child's stdout and stderr are appended to logPath so a startup failure
 * is diagnosable after the fact, and poll() reaps the child so it cannot
 * linger as a zombie.
 */

#include <android/log.h>
#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

#define LOG_TAG "fdlauncher"
#define LOGF(fmt, ...) \
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, fmt, ##__VA_ARGS__)

/*
 * Returns the child pid, or -1. On failure errno describes the reason.
 */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativeSpawnWithFd(
        JNIEnv *env, jobject thiz, jstring jPath, jobjectArray jArgs,
        jint fd, jstring jLogPath) {
    (void) thiz;
    const char *path = (*env)->GetStringUTFChars(env, jPath, NULL);
    const char *logPath = jLogPath ? (*env)->GetStringUTFChars(env, jLogPath, NULL) : NULL;
    if (path == NULL) {
        return -1;
    }

    /* argv[0] must be the program path; argv[1..] come from the caller. */
    jsize argCount = jArgs ? (*env)->GetArrayLength(env, jArgs) : 0;
    char **argv = (char **) calloc((size_t) argCount + 2, sizeof(char *));
    if (argv == NULL) {
        (*env)->ReleaseStringUTFChars(env, jPath, path);
        if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
        return -1;
    }
    argv[0] = (char *) path;
    int slot = 1;
    for (jsize i = 0; i < argCount; i++) {
        jstring arg = (jstring) (*env)->GetObjectArrayElement(env, jArgs, i);
        const char *utf = (*env)->GetStringUTFChars(env, arg, NULL);
        argv[slot++] = utf ? strdup(utf) : strdup("");
        if (utf) (*env)->ReleaseStringUTFChars(env, arg, utf);
        (*env)->DeleteLocalRef(env, arg);
    }
    argv[slot] = NULL;

    /* Open the log before forking so both sides agree on the descriptor. */
    int logFd = -1;
    if (logPath != NULL) {
        logFd = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    }

    pid_t pid = fork();
    if (pid < 0) {
        LOGF("fork failed: %s", strerror(errno));
        if (logFd >= 0) close(logFd);
        for (int i = 1; i < slot; i++) free(argv[i]);
        free(argv);
        (*env)->ReleaseStringUTFChars(env, jPath, path);
        if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
        return -1;
    }

    if (pid == 0) {
        /* Child. */
        if (logFd >= 0) {
            dup2(logFd, STDOUT_FILENO);
            dup2(logFd, STDERR_FILENO);
            if (logFd > STDERR_FILENO) close(logFd);
        }
        /*
         * The engine reads the tunnel from fd 3. Copy the descriptor the VPN
         * service gave us there; the original stays open in the parent, which
         * keeps ownership for its own close().
         */
        if (dup2(fd, 3) < 0) {
            /* Report through the log fd; the parent sees exit code 126. */
            LOGF("dup2(fd=%d, 3) failed: %s", fd, strerror(errno));
            _exit(126);
        }
        /* Keep the child from holding the parent's other descriptors. */
        for (int d = 4; d < 64; d++) {
            close(d);
        }
        execv(path, argv);
        /* execv only returns on failure; 127 tells the caller so. */
        LOGF("execv(\"%s\") failed: %s", path, strerror(errno));
        _exit(127);
    }

    /* Parent. */
    if (logFd >= 0) close(logFd);
    for (int i = 1; i < slot; i++) free(argv[i]);
    free(argv);
    (*env)->ReleaseStringUTFChars(env, jPath, path);
    if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
    return (jint) pid;
}

/*
 * Returns -1 while the child runs, otherwise its exit code (0..255).
 * A negative code other than -1 is returned as 128 + signal.
 */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativePollPid(
        JNIEnv *env, jobject thiz, jint pid) {
    (void) env;
    (void) thiz;
    if (pid <= 0) {
        return -1;
    }
    int status = 0;
    pid_t result = waitpid((pid_t) pid, &status, WNOHANG);
    if (result == 0) {
        return -1; /* still running */
    }
    if (result < 0) {
        return errno == ECHILD ? 0 : -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return -1;
}

/*
 * Signal a child (SIGTERM then SIGKILL semantics live on the caller side).
 * Returns 0 on success, -1 with errno set otherwise.
 */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativeKillPid(
        JNIEnv *env, jobject thiz, jint pid, jint sig) {
    (void) env;
    (void) thiz;
    if (pid <= 0) {
        return -1;
    }
    return kill((pid_t) pid, sig) == 0 ? 0 : -1;
}

/*
 * Reap a child that outlived the tunnel (used by stop()). Returns the same
 * codes as poll() but blocks until the child is gone.
 */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativeWaitPid(
        JNIEnv *env, jobject thiz, jint pid) {
    (void) env;
    (void) thiz;
    if (pid <= 0) {
        return -1;
    }
    int status = 0;
    pid_t result = waitpid((pid_t) pid, &status, 0);
    if (result < 0) {
        return errno == ECHILD ? 0 : -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return -1;
}
