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
#include <mutex>
#include <sstream>
#include <thread>
#include <vector>

using namespace std::chrono_literals;
struct Lab final : blackout::OpenVpnCallbacks {
    std::atomic<bool> online{false}, ever{false}, seen_loss{false};
    std::atomic<int> peer{-1};
    std::atomic<unsigned> protected_count{0}, established_count{0};
    std::mutex address_lock;
    std::string v4;
    std::string current_v4() {
        std::lock_guard<std::mutex> guard(address_lock);
        return v4;
    }
    bool reset() override {
        std::lock_guard<std::mutex> guard(address_lock);
        v4.clear();
        return true;
    }
    bool address(const std::string& ip, int) override {
        std::lock_guard<std::mutex> guard(address_lock);
        if (ip.find(':') == std::string::npos) v4 = ip;
        return true;
    }
    bool route(const std::string&, int) override { return true; }
    bool dns(const std::string&) override { return true; }
    bool mtu(int) override { return true; }
    bool protect(int) override { ++protected_count; return true; }
    int establish() override {
        int fds[2];
        if (current_v4().empty() || socketpair(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0, fds)) return -1;
        int previous = peer.exchange(fds[1]);
        if (previous >= 0) close(previous);
        ++established_count;
        return fds[0];
    }
    void connected(bool value) override {
        if (value) ever.store(true);
        else if (ever.load()) seen_loss.store(true);
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
    if (inet_pton(AF_INET, lab.current_v4().c_str(), packet.data()+12)!=1 ||
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
// A small, bounded TCP fixture: SYN, ACK, echo payload and ACK.
// This is not a general-purpose TCP implementation.
static uint32_t get32(const unsigned char* p) {
    return (uint32_t(p[0])<<24)|(uint32_t(p[1])<<16)|(uint32_t(p[2])<<8)|p[3];
}
static void put32(unsigned char* p,uint32_t v) {
    p[0]=v>>24; p[1]=v>>16; p[2]=v>>8; p[3]=v;
}
static bool exchange_tcp(Lab& lab) {
    const std::string payload="blackout-tcp-echo-fixture";
    static unsigned sequence=0;
    const unsigned src=30000+(static_cast<unsigned>(getpid())+sequence++)%10000;
    constexpr unsigned dst=41004;
    constexpr uint32_t initial=12345678;
    std::array<unsigned char,4> from{},to{};
    if(inet_pton(AF_INET,lab.current_v4().c_str(),from.data())!=1 ||
       inet_pton(AF_INET,"10.77.0.1",to.data())!=1) return false;
    auto send_segment=[&](uint32_t seq,uint32_t ack,unsigned char flags,const std::string& data) {
        std::vector<unsigned char> p(40+data.size(),0);
        p[0]=0x45; p[2]=p.size()>>8; p[3]=p.size(); p[8]=64; p[9]=6;
        std::copy(from.begin(),from.end(),p.begin()+12);
        std::copy(to.begin(),to.end(),p.begin()+16);
        auto ipcs=checksum(p.data(),20); p[10]=ipcs>>8; p[11]=ipcs;
        p[20]=src>>8; p[21]=src&255; p[22]=dst>>8; p[23]=dst&255;
        put32(p.data()+24,seq); put32(p.data()+28,ack);
        p[32]=0x50; p[33]=flags; p[34]=0xff; p[35]=0xff;
        std::copy(data.begin(),data.end(),p.begin()+40);
        std::vector<unsigned char> pseudo(12+p.size()-20+(data.size()%2),0);
        std::copy(p.begin()+12,p.begin()+20,pseudo.begin());
        pseudo[9]=6; auto tcp_len=p.size()-20;
        pseudo[10]=tcp_len>>8; pseudo[11]=tcp_len;
        std::copy(p.begin()+20,p.end(),pseudo.begin()+12);
        auto tcpcs=checksum(pseudo.data(),pseudo.size()); p[36]=tcpcs>>8; p[37]=tcpcs;
        return send(lab.peer.load(),p.data(),p.size(),0)==static_cast<ssize_t>(p.size());
    };
    if(!send_segment(initial,0,0x02,"")) return false;
    uint32_t remote_next=0;
    bool handshaken=false;
    std::string received;
    auto until=std::chrono::steady_clock::now()+6s;
    while(lab.online.load() && std::chrono::steady_clock::now()<until) {
        pollfd fd{lab.peer.load(),POLLIN,0};
        if(poll(&fd,1,100)<=0) continue;
        std::array<unsigned char,2048> p{};
        auto len=recv(fd.fd,p.data(),p.size(),0);
        if(len<40 || p[0]!=0x45 || p[9]!=6 ||
           !std::equal(to.begin(),to.end(),p.begin()+12) ||
           !std::equal(from.begin(),from.end(),p.begin()+16) ||
           p[20]!=(dst>>8)||p[21]!=(dst&255)||p[22]!=(src>>8)||p[23]!=(src&255)) continue;
        const unsigned h=20+(p[32]>>4)*4;
        if(h<40 || h>static_cast<unsigned>(len)) return false;
        const auto seq=get32(p.data()+24), ack=get32(p.data()+28);
        if(p[33]&0x04) return false;
        if(!handshaken && (p[33]&0x12)==0x12 && ack==initial+1) {
            remote_next=seq+1;
            if(!send_segment(initial+1,remote_next,0x10,"") ||
               !send_segment(initial+1,remote_next,0x18,payload)) return false;
            handshaken=true;
        } else if(handshaken && seq==remote_next && static_cast<unsigned>(len)>h) {
            received.append(reinterpret_cast<const char*>(p.data()+h),len-h);
            remote_next+=len-h;
            if(!send_segment(initial+1+payload.size(),remote_next,0x10,"")) return false;
            if(received==payload) {
                send_segment(initial+1+payload.size(),remote_next,0x14,"");
                return true;
            }
            if(received.size()>=payload.size()) return false;
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
    bool reject=mode=="tls13-no-downgrade" || mode=="bad-login" || mode=="bad-key" || mode=="bad-ca" || mode=="bad-name" || mode=="missing-name" || mode=="missing-dns" || mode=="bypass-dns" || mode=="partial-v6";
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
    auto deadline=std::chrono::steady_clock::now()+(mode=="tls13-no-downgrade"?36s:18s);
    while(!ended.load() && !lab.online.load() && std::chrono::steady_clock::now()<deadline)
        std::this_thread::sleep_for(20ms);
    const bool udp_data=!reject && lab.online.load() && exchange(lab);
    const bool tcp_data=udp_data && exchange_tcp(lab);
    bool data=udp_data && tcp_data;
    const bool recovery=mode=="reconnect" || mode=="server-restart";
    bool recovered=false;
    if (data && recovery) {
        if (mode=="reconnect") {
            client.reconnect(0);
        } else {
            std::ofstream marker("recovery.ready");
            marker << "ready\n";
        }
        auto limit=std::chrono::steady_clock::now()+30s;
        while (!ended.load() && std::chrono::steady_clock::now()<limit) {
            if (lab.seen_loss.load() && lab.established_count.load()>=2 && lab.online.load()) {
                recovered=exchange(lab) && exchange_tcp(lab);
                break;
            }
            std::this_thread::sleep_for(20ms);
        }
        data=data && recovered;
    }
    const bool finished=ended.load();
    if(!finished) client.cancel();
    worker.join();
    const bool ok=reject ? (finished && result.load()!=0 && !lab.ever.load() && lab.established_count==0)
        : (data && lab.ever.load() && lab.protected_count>0 && lab.established_count==(recovery?2u:1u));
    std::cout << (ok?"PASS ":"FAIL ") << mode << " connected=" << lab.ever.load()
        << " udp=" << udp_data << " tcp=" << tcp_data << " protected=" << lab.protected_count
        << " tun=" << lab.established_count << " result=" << result.load()
        << " recovered=" << recovered << " finished_before_cancel=" << finished << "\n";
    return ok?0:1;
}
