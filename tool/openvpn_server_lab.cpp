// Isolated host interoperability test. Socketpair substitutes for Android TUN.
#include <client/ovpncli.cpp>
#include "../android/app/src/main/cpp/openvpn_client_adapter.hpp"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <poll.h>
#include <unistd.h>
#include <array>
#include <atomic>
#include <chrono>
#include <fstream>
#include <iostream>
#include <sstream>
#include <thread>
#include <vector>

using namespace std::chrono_literals;
struct Lab final : blackout::OpenVpnCallbacks {
    std::atomic<bool> online{false}, ever{false};
    std::atomic<int> peer{-1};
    std::atomic<unsigned> protected_count{0}, established_count{0};
    std::string v4;
    bool reset() override { v4.clear(); return peer.load() == -1; }
    bool address(const std::string& ip, int) override {
        if (ip.find(':') == std::string::npos) v4 = ip;
        return true;
    }
    bool route(const std::string&, int) override { return true; }
    bool dns(const std::string&) override { return true; }
    bool mtu(int) override { return true; }
    bool protect(int) override { ++protected_count; return true; }
    int establish() override {
        int fds[2];
        if (v4.empty() || socketpair(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0, fds)) return -1;
        peer.store(fds[1]);
        ++established_count;
        return fds[0];
    }
    void connected(bool value) override {
        if (value) ever.store(true);
        online.store(value);
    }
    ~Lab() { if (peer.load() >= 0) close(peer.load()); }
};

static uint16_t checksum(const unsigned char* bytes, size_t n) {
    unsigned sum = 0;
    for (size_t i=0;i<n;i+=2) sum += (unsigned(bytes[i]) << 8) | bytes[i+1];
    while (sum >> 16) sum = (sum & 65535) + (sum >> 16);
    return uint16_t(~sum);
}
static bool exchange(Lab& lab) {
    constexpr char payload[] = "blackout-loopback-echo";
    const size_t n = sizeof(payload)-1;
    std::vector<unsigned char> packet(28+n, 0);
    packet[0]=0x45; packet[2]=packet.size()>>8; packet[3]=packet.size()&255;
    packet[8]=64; packet[9]=17;
    if (inet_pton(AF_INET, lab.v4.c_str(), packet.data()+12)!=1 ||
        inet_pton(AF_INET, "10.77.0.1", packet.data()+16)!=1) return false;
    auto cs=checksum(packet.data(),20); packet[10]=cs>>8; packet[11]=cs&255;
    const unsigned src=41001,dst=41002;
    packet[20]=src>>8; packet[21]=src&255; packet[22]=dst>>8; packet[23]=dst&255;
    packet[24]=(8+n)>>8; packet[25]=(8+n)&255;
    std::copy(payload,payload+n,packet.begin()+28);
    for (int attempt=0;attempt<4;++attempt) {
        if (!lab.online.load()) return false;
        if (send(lab.peer.load(),packet.data(),packet.size(),0)!=static_cast<ssize_t>(packet.size())) return false;
        auto until=std::chrono::steady_clock::now()+1s;
        while (std::chrono::steady_clock::now()<until) {
            pollfd p{lab.peer.load(),POLLIN,0};
            if(poll(&p,1,100)<=0) continue;
            std::array<unsigned char,2048> reply{};
            auto len=recv(p.fd,reply.data(),reply.size(),0);
            if(len<28 || reply[0]!=0x45 || reply[9]!=17) continue;
            if(reply[20]!=(dst>>8) || reply[21]!=(dst&255) ||
                reply[22]!=(src>>8) || reply[23]!=(src&255)) continue;
            if(len==static_cast<ssize_t>(28+n) &&
                std::equal(payload,payload+n,reply.begin()+28) &&
                std::equal(packet.begin()+12,packet.begin()+16,reply.begin()+16) &&
                std::equal(packet.begin()+16,packet.begin()+20,reply.begin()+12)) return true;
        }
    }
    return false;
}
int main(int argc,char** argv) {
    if(argc!=3) return 2;
    std::ifstream in(argv[1]); std::ostringstream profile; profile<<in.rdbuf();
    if(!in.good() && !in.eof()) return 2;
    std::string mode=argv[2];
    bool auth=mode=="login" || mode=="bad-login" || mode=="login-only";
    bool key=mode=="encrypted" || mode=="bad-key";
    bool reject=mode=="bad-login" || mode=="bad-key" || mode=="bad-ca";
    Lab lab;
    openvpn::Stop stop;
    std::atomic<bool> cancelled{false}, ended{false};
    std::atomic<int> result{99};
    blackout::OpenVpnClient client(lab,stop,cancelled);
    std::thread worker([&] {
        try {
            result.store(client.run(profile.str(),auth?"fixture-user":"",
                auth?(mode=="bad-login"?"incorrect":"fixture-password"):"",
                key?(mode=="bad-key"?"incorrect":"fixture-key-password"):""));
        } catch (...) { result.store(98); }
        ended.store(true);
    });
    auto deadline=std::chrono::steady_clock::now()+18s;
    while(!ended.load() && !lab.online.load() && std::chrono::steady_clock::now()<deadline)
        std::this_thread::sleep_for(20ms);
    const bool data=!reject && lab.online.load() && exchange(lab);
    const bool finished=ended.load();
    if(!finished) client.cancel();
    worker.join();
    const bool ok=reject ? (finished && result.load()!=0 && !lab.ever.load() && lab.established_count==0)
        : (data && lab.ever.load() && lab.protected_count>0 && lab.established_count==1);
    std::cout << (ok?"PASS ":"FAIL ") << mode << " connected=" << lab.ever.load()
        << " data=" << data << " protected=" << lab.protected_count
        << " tun=" << lab.established_count << " result=" << result.load()
        << " finished_before_cancel=" << finished << "\n";
    return ok?0:1;
}
