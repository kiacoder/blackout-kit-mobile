#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct go_string { const char *str; long n; };

extern int wgTurnOn(struct go_string, int, struct go_string);
extern void wgTurnOff(int);
extern int wgGetSocketV4(int);
extern int wgGetSocketV6(int);
extern char *wgGetConfig(int);
extern char *wgVersion(void);
extern int wgIsClosed(int);

extern int awgTurnOn(struct go_string, int, struct go_string);
extern void awgTurnOff(int);
extern int awgGetSocketV4(int);
extern int awgGetSocketV6(int);
extern char *awgGetConfig(int);
extern char *awgVersion(void);
extern int awgIsClosed(int);

static int turn_on(JNIEnv *env, jstring ifname, jint tun_fd, jstring settings,
                   int (*fn)(struct go_string, int, struct go_string))
{
    const char *ifname_str = (*env)->GetStringUTFChars(env, ifname, 0);
    if (!ifname_str) {
        close(tun_fd);
        return -1;
    }
    size_t ifname_len = (*env)->GetStringUTFLength(env, ifname);
    const char *settings_str = (*env)->GetStringUTFChars(env, settings, 0);
    if (!settings_str) {
        (*env)->ReleaseStringUTFChars(env, ifname, ifname_str);
        close(tun_fd);
        return -1;
    }
    size_t settings_len = (*env)->GetStringUTFLength(env, settings);
    int result = fn(
        (struct go_string){ .str = ifname_str, .n = (long)ifname_len },
        tun_fd,
        (struct go_string){ .str = settings_str, .n = (long)settings_len }
    );
    (*env)->ReleaseStringUTFChars(env, ifname, ifname_str);
    (*env)->ReleaseStringUTFChars(env, settings, settings_str);
    return result;
}

static jstring take_string(JNIEnv *env, char *value)
{
    if (!value)
        return NULL;
    jstring result = (*env)->NewStringUTF(env, value);
    free(value);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_wireguard_android_backend_GoBackend_wgTurnOn(
    JNIEnv *env, jclass clazz, jstring ifname, jint tun_fd, jstring settings)
{
    return turn_on(env, ifname, tun_fd, settings, wgTurnOn);
}

JNIEXPORT void JNICALL
Java_com_wireguard_android_backend_GoBackend_wgTurnOff(
    JNIEnv *env, jclass clazz, jint handle)
{
    wgTurnOff(handle);
}

JNIEXPORT jint JNICALL
Java_com_wireguard_android_backend_GoBackend_wgGetSocketV4(
    JNIEnv *env, jclass clazz, jint handle)
{
    return wgGetSocketV4(handle);
}

JNIEXPORT jint JNICALL
Java_com_wireguard_android_backend_GoBackend_wgGetSocketV6(
    JNIEnv *env, jclass clazz, jint handle)
{
    return wgGetSocketV6(handle);
}

JNIEXPORT jstring JNICALL
Java_com_wireguard_android_backend_GoBackend_wgGetConfig(
    JNIEnv *env, jclass clazz, jint handle)
{
    return take_string(env, wgGetConfig(handle));
}

JNIEXPORT jstring JNICALL
Java_com_wireguard_android_backend_GoBackend_wgVersion(
    JNIEnv *env, jclass clazz)
{
    return take_string(env, wgVersion());
}

JNIEXPORT jint JNICALL
Java_com_wireguard_android_backend_GoBackend_wgIsClosed(
    JNIEnv *env, jclass clazz, jint handle)
{
    return wgIsClosed(handle);
}

JNIEXPORT jint JNICALL
Java_org_amnezia_awg_GoBackend_awgTurnOn(
    JNIEnv *env, jclass clazz, jstring ifname, jint tun_fd, jstring settings)
{
    return turn_on(env, ifname, tun_fd, settings, awgTurnOn);
}

JNIEXPORT void JNICALL
Java_org_amnezia_awg_GoBackend_awgTurnOff(
    JNIEnv *env, jclass clazz, jint handle)
{
    awgTurnOff(handle);
}

JNIEXPORT jint JNICALL
Java_org_amnezia_awg_GoBackend_awgGetSocketV4(
    JNIEnv *env, jclass clazz, jint handle)
{
    return awgGetSocketV4(handle);
}

JNIEXPORT jint JNICALL
Java_org_amnezia_awg_GoBackend_awgGetSocketV6(
    JNIEnv *env, jclass clazz, jint handle)
{
    return awgGetSocketV6(handle);
}

JNIEXPORT jstring JNICALL
Java_org_amnezia_awg_GoBackend_awgGetConfig(
    JNIEnv *env, jclass clazz, jint handle)
{
    return take_string(env, awgGetConfig(handle));
}

JNIEXPORT jstring JNICALL
Java_org_amnezia_awg_GoBackend_awgVersion(
    JNIEnv *env, jclass clazz)
{
    return take_string(env, awgVersion());
}

JNIEXPORT jint JNICALL
Java_org_amnezia_awg_GoBackend_awgIsClosed(
    JNIEnv *env, jclass clazz, jint handle)
{
    return awgIsClosed(handle);
}
