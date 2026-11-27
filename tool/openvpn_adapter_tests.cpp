#include <client/ovpncli.cpp>
#include "../android/app/src/main/cpp/openvpn_client_adapter.hpp"
#include <cassert>
#include <iostream>
#include <fstream>
#include <sstream>

struct Fake final : blackout::OpenVpnCallbacks {
    int protected_count = 0, established_count = 0, routes = 0;
    bool protect_ok = true, state = false;
    bool reset() override { return true; }
    bool address(const std::string&, int) override { return true; }
    bool route(const std::string&, int) override { ++routes; return true; }
    bool dns(const std::string&) override { return true; }
    bool mtu(int) override { return true; }
    bool protect(int) override { ++protected_count; return protect_ok; }
    int establish() override { ++established_count; return 42; }
    void connected(bool value) override { state = value; }
};
openvpn::DnsOptions dns_options() {
    openvpn::DnsOptions options;
    openvpn::DnsAddress addr;
    addr.address = "192.0.2.53";
    options.servers[0].addresses.push_back(addr);
    return options;
}
int main(int argc, char** argv) {
    {
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        assert(c.tun_builder_new());
        assert(c.socket_protect(7, "", false));
        assert(c.tun_builder_add_address("192.0.2.2", 24, "", false, false));
        assert(c.tun_builder_add_address("2001:db8::2", 64, "", true, false));
        assert(c.tun_builder_reroute_gw(true, true, 0));
        assert(c.tun_builder_set_allow_family(AF_INET, true));
        assert(c.tun_builder_set_allow_family(AF_INET6, true));
        assert(c.tun_builder_set_dns_options(dns_options()));
        assert(c.tun_builder_establish() == 42);
        assert(f.routes == 2 && f.established_count == 1 && f.protected_count == 1);
        openvpn::ClientAPI::Event e;
        e.name = "CONNECTED";
        c.event(e);
        assert(f.state);
        c.tun_builder_teardown(true);
        assert(!f.state);
    }
    {
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        assert(c.tun_builder_new());
        assert(c.tun_builder_establish() == -1);
        assert(f.established_count == 0);
    }
    {
        Fake f;
        f.protect_ok = false;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        assert(!c.socket_protect(8, "", false));
        assert(!c.tun_builder_new());
    }
    {
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        assert(c.tun_builder_new());
        assert(!c.tun_builder_exclude_route("192.0.2.0", 24, 0, false));
        assert(c.tun_builder_establish() == -1);
    }
    {
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        auto options = dns_options();
        options.servers[0].transport = openvpn::DnsServer::Transport::TLS;
        assert(!c.tun_builder_set_dns_options(options));
    }
    {
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        c.cancel();
        assert(!c.tun_builder_new());
        assert(c.run("client", "", "") != 0);
        assert(f.established_count == 0);
    }
    {
        const std::string profile = "client\ndev tun\nproto udp\nremote fixture.test 1194\nauth-user-pass\n";
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        assert(!c.prepare(profile, "", ""));
        assert(f.protected_count == 0 && f.established_count == 0);
    }
    {
        const std::string profile = "client\ndev tun\nproto udp\nremote fixture.test 1194\nauth-user-pass\n";
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient c(f, stop, flag);
        assert(c.prepare(profile, "fixture-user", "fixture-password"));
        assert(f.protected_count == 0 && f.established_count == 0);
    }
    if (argc == 2) {
        std::ifstream fixture(argv[1]);
        assert(fixture.good());
        std::ostringstream text;
        text << fixture.rdbuf();
        Fake f;
        openvpn::Stop stop;
        std::atomic<bool> flag{false};
        blackout::OpenVpnClient missing(f, stop, flag);
        assert(!missing.prepare(text.str(), "", ""));
        blackout::OpenVpnClient supplied(f, stop, flag);
        assert(supplied.prepare(text.str(), "", "", "fixture-key-password"));
        assert(f.protected_count == 0 && f.established_count == 0);
        std::cout << "2 encrypted PEM preparation cases passed (no network)\n";
    }
    std::cout << "8 OpenVPN callback and authentication preparation tests passed\n";
}
