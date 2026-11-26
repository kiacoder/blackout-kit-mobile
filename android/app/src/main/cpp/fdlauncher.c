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
 *   spawn(path, args, fd, logPath) -> opaque child token (or -1 on failure)
 *   poll(token)                    -> -1 still running, >= 0 terminal status
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
#include "parent_guard.h"
#include "owned_child.h"
#include "descriptor_guard.h"
#include <pthread.h>
#include <limits.h>

static pthread_mutex_t child_lock = PTHREAD_MUTEX_INITIALIZER;
static owned_child bridge = {0, 0, CHILD_UNKNOWN};

#define LOG_TAG "fdlauncher"
#define LOGF(fmt, ...) \
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, fmt, ##__VA_ARGS__)

/*
 * Returns an opaque child token, or -1 on failure.
 */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativeSpawnWithFd(
        JNIEnv *env, jobject thiz, jstring jPath, jobjectArray jArgs,
        jint fd, jstring jLogPath) {
    (void) thiz;
    const char *path = (*env)->GetStringUTFChars(env, jPath, NULL);
    if (path == NULL) return -1;
    const char *logPath = jLogPath ? (*env)->GetStringUTFChars(env, jLogPath, NULL) : NULL;
    if (jLogPath && !logPath) {
        (*env)->ReleaseStringUTFChars(env, jPath, path);
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
        const char *utf = arg ? (*env)->GetStringUTFChars(env, arg, NULL) : NULL;
        char *copy = utf ? strdup(utf) : NULL;
        if (utf) (*env)->ReleaseStringUTFChars(env, arg, utf);
        if (arg) (*env)->DeleteLocalRef(env, arg);
        if (!copy) {
            for (int k = 1; k < slot; k++) free(argv[k]);
            free(argv);
            (*env)->ReleaseStringUTFChars(env, jPath, path);
            if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
            return -1;
        }
        argv[slot++] = copy;
    }
    argv[slot] = NULL;

    /* Open the log before forking so both sides agree on the descriptor. */
    int logFd = -1;
    if (logPath != NULL) {
        logFd = open(logPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
        if (logFd < 0) {
            for (int i = 1; i < slot; i++) free(argv[i]);
            free(argv);
            (*env)->ReleaseStringUTFChars(env, jPath, path);
            (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
            return -1;
        }
    }

    /* The launcher has exactly one bridge slot. Tokens never wrap or reuse. */
    pthread_mutex_lock(&child_lock);
    if (bridge.pid > 0 || bridge.token == INT_MAX) {
        pthread_mutex_unlock(&child_lock);
        if (logFd >= 0) close(logFd);
        for (int i = 1; i < slot; i++) free(argv[i]);
        free(argv);
        (*env)->ReleaseStringUTFChars(env, jPath, path);
        if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
        return -1;
    }
    pid_t expected_parent = getpid();
    pid_t pid = fork();
    if (pid < 0) {
        pthread_mutex_unlock(&child_lock);
        LOGF("fork failed: %s", strerror(errno));
        if (logFd >= 0) close(logFd);
        for (int i = 1; i < slot; i++) free(argv[i]);
        free(argv);
        (*env)->ReleaseStringUTFChars(env, jPath, path);
        if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
        return -1;
    }

    if (pid == 0) {
        /* Child: never keep the TUN alive beyond its launcher owner. */
        if (arm_parent_guard(expected_parent) != 0) {
            _exit(126);
        }
        /*
         * First, duplicate the VPN tunnel descriptor to a safe high slot so
         * stdout/stderr redirection and logFd manipulation cannot clobber it
         * if fd happened to be 0, 1, 2, or 3.
         */
        int vpnFd = fcntl(fd, F_DUPFD_CLOEXEC, 100);
        if (vpnFd < 0) {
            _exit(126);
        }

        if (logFd >= 0) {
            if (dup2(logFd, STDOUT_FILENO) < 0 ||
                dup2(logFd, STDERR_FILENO) < 0 ||
                fcntl(STDOUT_FILENO, F_SETFD, 0) < 0 ||
                fcntl(STDERR_FILENO, F_SETFD, 0) < 0) {
                _exit(126);
            }
            if (logFd != STDOUT_FILENO && logFd != STDERR_FILENO) {
                close(logFd);
            }
        }

        /* Never inherit the app's standard input. */
        int nullInput = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (nullInput < 0 || dup2(nullInput, STDIN_FILENO) < 0 ||
            fcntl(STDIN_FILENO, F_SETFD, 0) < 0) {
            _exit(126);
        }
        if (nullInput != STDIN_FILENO) close(nullInput);

        /*
         * The engine reads the tunnel from fd 3. Copy the descriptor there.
         */
        if (dup2(vpnFd, 3) < 0) {
            /* Avoid non-async-signal-safe logging after fork. */
            _exit(126);
        }

        /*
         * CRUCIAL: Clear FD_CLOEXEC on fd 3!
         * If fd was already 3 (the first free descriptor returned by
         * ParcelFileDescriptor.dup() in Java), POSIX specifies that dup2(3, 3)
         * is a no-op that leaves FD_CLOEXEC UNCHANGED. On execv(), the kernel
         * then closed fd 3, causing tun2socks to immediately crash with:
         * "unix.SetNonblock(3) failed: bad file descriptor (EBADF)".
         */
        if (fcntl(3, F_SETFD, 0) < 0) _exit(126);

        /* Keep only standard streams and the explicitly mapped TUN. */
        if (close_extra_descriptors() != 0) _exit(126);
        execv(path, argv);
        /* execv only returns on failure; 127 tells the caller so. */
        _exit(127);
    }

    /* Parent: publish ownership before any caller can poll or signal. */
    bridge.pid = pid;
    int token = ++bridge.token;
    bridge.terminal_status = CHILD_UNKNOWN;
    pthread_mutex_unlock(&child_lock);
    if (logFd >= 0) close(logFd);
    for (int i = 1; i < slot; i++) free(argv[i]);
    free(argv);
    (*env)->ReleaseStringUTFChars(env, jPath, path);
    if (logPath) (*env)->ReleaseStringUTFChars(env, jLogPath, logPath);
    return (jint) token;
}

/* Poll by opaque launcher token, not by an OS PID. */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativePollChild(
        JNIEnv *env, jobject thiz, jint token) {
    (void) env;
    (void) thiz;
    pthread_mutex_lock(&child_lock);
    int result = owned_child_poll(&bridge, token);
    pthread_mutex_unlock(&child_lock);
    return result;
}

/* Check and signal under the same lock as the sole launcher reaper. */
JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_EngineRunner_nativeSignalChild(
        JNIEnv *env, jobject thiz, jint token, jint sig) {
    (void) env;
    (void) thiz;
    pthread_mutex_lock(&child_lock);
    int result = owned_child_signal(&bridge, token, sig);
    pthread_mutex_unlock(&child_lock);
    return result;
}
