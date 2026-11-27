#pragma once
// Candidate only: no production runtime registration. Uses the pinned OpenVPN 3 API.
// Include client/ovpncli.cpp first in the owning translation unit.
#include <openvpn/common/stop.hpp>
#include <atomic>
#include <string>

namespace blackout {
struct OpenVpnCallbacks {
    virtual ~OpenVpnCallbacks() = default;
    virtual bool reset() = 0;
    virtual bool address(const std::string&, int) = 0;
    virtual bool route(const std::string&, int) = 0;
    virtual bool dns(const std::string&) = 0;
    virtual bool mtu(int) = 0;
    virtual bool protect(int) = 0;
    virtual int establish() = 0;
    virtual void connected(bool) = 0;
};

class OpenVpnClient final : public openvpn::ClientAPI::OpenVPNClient {
    using Config = openvpn::ClientAPI::Config;
    OpenVpnCallbacks& cb;
    openvpn::Stop& cancellation;
    std::atomic<bool>& cancelled;
    bool full4 = false;
    bool full6 = false;
    bool address4 = false;
    bool address6 = false;
    bool dns_added = false;
    bool failed = false;
    bool established = false;

    bool gate(bool ok) {
        if (!ok) failed = true;
        return ok;
    }
    bool active() const { return !cancelled.load() && !failed; }
protected:
    openvpn::Stop* get_async_stop() override { return &cancellation; }
public:
    OpenVpnClient(OpenVpnCallbacks& callbacks, openvpn::Stop& stop, std::atomic<bool>& flag)
        : cb(callbacks), cancellation(stop), cancelled(flag) {}
    void cancel() {
        cancelled.store(true);
        cancellation.stop();
    }
    bool prepare(const std::string& profile, const std::string& user, const std::string& password) {
        if (cancelled.load() || profile.empty() || profile.size() > 1048576 ||
            profile.find('\0') != std::string::npos) return false;
        openvpn::ClientAPI::OpenVPNClientHelper helper;
        auto merged = helper.merge_config_string(profile);
        if (merged.status != "MERGE_SUCCESS" || !merged.refPathList.empty()) return false;
        Config config;
        config.content = std::move(merged.profileContent);
        config.connTimeout = 30;
        config.tunPersist = false;
        config.googleDnsFallback = false;
        config.allowUnusedAddrFamilies = "no";
        config.compressionMode = "no";
        config.tlsVersionMinOverride = "tls_1_2";
        auto eval = helper.eval_config(config);
        if (eval.error || eval.privateKeyPasswordRequired ||
            !eval.staticChallenge.empty()) return false;
        // The service requires a complete inline cert/key pair or explicit
        // user/password mode. A credential-only profile may omit the client cert.
        if (eval.externalPki) {
            if (eval.autologin || user.empty() || password.empty()) return false;
            config.disableClientCert = true;

        }
        eval = eval_config(config);
        if (eval.error) return false;
        if (!eval.autologin) {
            if (user.empty() || password.empty()) return false;
            openvpn::ClientAPI::ProvideCreds credentials;
            credentials.username = user;
            credentials.password = password;
            if (provide_creds(credentials).error) return false;
        }
        return !cancelled.load();
    }
    int run(const std::string& profile, const std::string& user, const std::string& password) {
        if (!prepare(profile, user, password)) return 1;
        const auto status = connect();
        cb.connected(false);
        return status.error || failed ? 1 : 0;
    }
    bool socket_protect(openvpn_io::detail::socket_type fd, std::string, bool) override {
        return active() && gate(cb.protect(fd));
    }
    bool tun_builder_new() override {
        full4 = full6 = address4 = address6 = dns_added = established = false;
        return active() && gate(cb.reset());
    }
    bool tun_builder_set_layer(int layer) override { return gate(layer == 3); }
    bool tun_builder_set_remote_address(const std::string&, bool) override { return active(); }
    bool tun_builder_add_address(const std::string& ip, int prefix, const std::string&, bool ipv6, bool) override {
        if (!active() || !gate(cb.address(ip, prefix))) return false;
        if (ipv6) address6 = true; else address4 = true;
        return true;
    }
    bool tun_builder_add_route(const std::string& ip, int prefix, int, bool) override {
        return active() && gate(cb.route(ip, prefix));
    }
    bool tun_builder_reroute_gw(bool ipv4, bool ipv6, unsigned int) override {
        full4 = ipv4;
        full6 = ipv6;
        return active() && gate((!ipv4 || cb.route("0.0.0.0", 0)) &&
                                (!ipv6 || cb.route("::", 0)));
    }
    bool tun_builder_exclude_route(const std::string&, int, int, bool) override { return gate(false); }
    // OpenVPN calls this even for full-tunnel profiles and ignores its return.
    // Android never calls Builder.allowFamily; unconfigured families stay blocked.
    bool tun_builder_set_allow_family(int, bool) override { return active(); }
    bool tun_builder_set_dns_options(const openvpn::DnsOptions& options) override {
        using Server = openvpn::DnsServer;
        if (!options.search_domains.empty()) return gate(false);
        for (const auto& pair : options.servers) {
            const auto& server = pair.second;
            if (!server.domains.empty() || !server.sni.empty() ||
                (server.transport != Server::Transport::Unset && server.transport != Server::Transport::Plain) ||
                (server.dnssec != Server::Security::Unset && server.dnssec != Server::Security::No))
                return gate(false);
            for (const auto& item : server.addresses) {
                if ((item.port != 0 && item.port != 53) || !active() || !cb.dns(item.address))
                    return gate(false);
                dns_added = true;
            }
        }
        return active();
    }
    bool tun_builder_set_mtu(int value) override { return active() && gate(cb.mtu(value)); }
    bool tun_builder_set_session_name(const std::string&) override { return active(); }
    bool tun_builder_persist() override { return false; }
    int tun_builder_establish() override {
        // Initial policy: IPv4 full tunnel required, other family must be blocked
        // by the platform if no address/route exists. No DNS fallback.
        if (!active() || !full4 || !address4 || !dns_added || (address6 && !full6) || (full6 && !address6)) { failed = true; return -1; }
        const int fd = cb.establish();
        established = fd >= 0;
        if (!established) failed = true;
        return fd;
    }
    void tun_builder_teardown(bool) override {
        established = false;
        cb.connected(false);
    }
    void event(const openvpn::ClientAPI::Event& e) override {
        if (e.name == "CONNECTED") cb.connected(active() && established);
        else if (e.error || e.name == "RECONNECTING" || e.name == "DISCONNECTED") cb.connected(false);
    }
    bool pause_on_connection_timeout() override { return false; }
    void acc_event(const openvpn::ClientAPI::AppCustomControlMessageEvent&) override {}
    void log(const openvpn::ClientAPI::LogInfo&) override {}
    void external_pki_cert_request(openvpn::ClientAPI::ExternalPKICertRequest& r) override { r.error = true; }
    void external_pki_sign_request(openvpn::ClientAPI::ExternalPKISignRequest& r) override { r.error = true; }
};
}
