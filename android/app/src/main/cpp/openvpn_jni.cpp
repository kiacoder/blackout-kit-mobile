// Experimental bridge, not registered with the production service.
#include <client/ovpncli.cpp>
#include "openvpn_client_adapter.hpp"
#include <jni.h>
#include <memory>
#include <mutex>
#if defined(USE_MBEDTLS)
#include <mbedtls/platform_util.h>
#else
#include <openssl/crypto.h>
#endif

namespace {
struct Session {
    openvpn::Stop stop;
    std::atomic<bool> cancelled{false};
    bool running = false;
    bool used = false;
};
std::mutex lock;
std::shared_ptr<Session> session;
jlong generation = 0;

std::shared_ptr<Session> lookup(jlong id) {
    std::lock_guard<std::mutex> guard(lock);
    return id > 0 && id == generation ? session : nullptr;
}

class Callbacks final : public blackout::OpenVpnCallbacks {
    JNIEnv* env;
    jobject target;
    jmethodID reset_id, address_id, route_id, dns_id, mtu_id, protect_id, establish_id, state_id;

    bool clean() {
        if (!env->ExceptionCheck()) return true;
        env->ExceptionClear();
        return false;
    }
    bool text(jmethodID id, const std::string& value, int prefix = -1) {
        if (value.empty() || value.size() > 256) return false;
        auto str = env->NewStringUTF(value.c_str());
        if (!clean() || !str) return false;
        const auto result = prefix < 0 ? env->CallBooleanMethod(target, id, str)
                                      : env->CallBooleanMethod(target, id, str, prefix);
        env->DeleteLocalRef(str);
        return clean() && result == JNI_TRUE;
    }
public:
    Callbacks(JNIEnv* e, jobject obj) : env(e), target(obj) {
        auto cls = env->GetObjectClass(obj);
        if (!cls || !clean()) throw std::runtime_error("callback");
        auto method = [&](const char* name, const char* signature) {
            auto id = env->GetMethodID(cls, name, signature);
            if (!clean() || !id) throw std::runtime_error("callback");
            return id;
        };
        reset_id = method("reset", "()Z");
        address_id = method("address", "(Ljava/lang/String;I)Z");
        route_id = method("route", "(Ljava/lang/String;I)Z");
        dns_id = method("dns", "(Ljava/lang/String;)Z");
        mtu_id = method("mtu", "(I)Z");
        protect_id = method("protect", "(I)Z");
        establish_id = method("establish", "()I");
        state_id = method("connected", "(Z)V");
        env->DeleteLocalRef(cls);
    }
    bool reset() override {
        const auto r = env->CallBooleanMethod(target, reset_id);
        return clean() && r == JNI_TRUE;
    }
    bool address(const std::string& ip, int p) override { return text(address_id, ip, p); }
    bool route(const std::string& ip, int p) override { return text(route_id, ip, p); }
    bool dns(const std::string& ip) override { return text(dns_id, ip); }
    bool mtu(int value) override {
        const auto r = env->CallBooleanMethod(target, mtu_id, value);
        return clean() && r == JNI_TRUE;
    }
    bool protect(int fd) override {
        const auto r = env->CallBooleanMethod(target, protect_id, fd);
        return clean() && r == JNI_TRUE;
    }
    int establish() override {
        const int r = env->CallIntMethod(target, establish_id);
        return clean() ? r : -1;
    }
    void connected(bool value) override {
        env->CallVoidMethod(target, state_id, static_cast<jboolean>(value));
        clean();
    }
};

bool read(JNIEnv* env, jbyteArray array, std::string& out, int limit) {
    if (!array) return false;
    const auto size = env->GetArrayLength(array);
    if (size < 0 || size > limit) return false;
    out.resize(size);
    if (size) env->GetByteArrayRegion(array, 0, size, reinterpret_cast<jbyte*>(out.data()));
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return false;
    }
    return out.find('\0') == std::string::npos;
}
// Kotlin declares Array<ByteArray>; reject null, wrong arity and oversized fields.
bool read_auth(JNIEnv* env, jobjectArray values, std::string& user,
               std::string& password, std::string& keyPassword) {
    if (!values || env->GetArrayLength(values) != 3) return false;
    std::string* fields[] = {&user, &password, &keyPassword};
    for (jsize i = 0; i < 3; ++i) {
        auto item = static_cast<jbyteArray>(env->GetObjectArrayElement(values, i));
        if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
        const bool ok = read(env, item, *fields[i], 4096);
        if (item) env->DeleteLocalRef(item);
        if (!ok) return false;
    }
    return true;
}
struct Sensitive {
    std::string value;
    ~Sensitive() {
        if (value.empty()) return;
#if defined(USE_MBEDTLS)
        mbedtls_platform_zeroize(value.data(), value.size());
#else
        OPENSSL_cleanse(value.data(), value.size());
#endif
    }
};
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_blackoutkit_vpn_OpenVpnNativeBridge_nativeCreate(JNIEnv*, jobject) {
    try {
        std::lock_guard<std::mutex> guard(lock);
        if (session || generation == INT64_MAX) return 0;
        session = std::make_shared<Session>();
        return ++generation;
    } catch (...) { return 0; }
}

extern "C" JNIEXPORT jint JNICALL
Java_com_blackoutkit_vpn_OpenVpnNativeBridge_nativeRunV3(
    JNIEnv* env, jobject, jlong id, jobject target, jbyteArray profile, jobjectArray authentication) {
    std::shared_ptr<Session> current;
    {
        std::lock_guard<std::mutex> guard(lock);
        if (id != generation || !session || session->used) return 1;
        current = session;
        current->running = current->used = true;
    }
    int result = 1;
    try {
        Sensitive raw, name, secret, keySecret;
        if (target && read(env, profile, raw.value, 1048576) &&
            read_auth(env, authentication, name.value, secret.value, keySecret.value)) {
            Callbacks callbacks(env, target);
            blackout::OpenVpnClient client(callbacks, current->stop, current->cancelled);
            result = client.run(raw.value, name.value, secret.value, keySecret.value);
        }
    } catch (...) { result = 1; }
    {
        std::lock_guard<std::mutex> guard(lock);
        current->running = false;
    }
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_blackoutkit_vpn_OpenVpnNativeBridge_nativeCancel(JNIEnv*, jobject, jlong id) {
    try {
        auto current = lookup(id);
        if (current) {
            current->cancelled.store(true);
            current->stop.stop();
        }
    } catch (...) {}
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_blackoutkit_vpn_OpenVpnNativeBridge_nativeRelease(JNIEnv*, jobject, jlong id) {
    std::lock_guard<std::mutex> guard(lock);
    if (id != generation || !session || session->running) return JNI_FALSE;
    session.reset();
    return JNI_TRUE;
}
