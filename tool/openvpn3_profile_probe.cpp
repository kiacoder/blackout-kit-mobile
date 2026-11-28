// Host-only probe for the pinned OpenVPN 3 ClientAPI. No network or TUN.
// Only bounded input and fixed diagnostic codes leave the adapter.
#include <client/ovpncli.cpp>
#include <array>
#include <iostream>
#include <string>

namespace {
constexpr std::size_t max_profile = 1024 * 1024;

int reject() {
    std::cout << "REJECTED\n";
    return 1;
}
}

int main() {
    try {
        std::string profile;
        std::array<char, 4096> buffer{};
        while (std::cin) {
            std::cin.read(buffer.data(), buffer.size());
            const auto size = static_cast<std::size_t>(std::cin.gcount());
            if (size > max_profile - profile.size()) return reject();
            profile.append(buffer.data(), size);
        }
        if (!std::cin.eof() || profile.empty() ||
            profile.find('\0') != std::string::npos) return reject();

        openvpn::ClientAPI::OpenVPNClientHelper helper;
        // The string merge API uses FOLLOW_NONE. Never merge a user path.
        const auto merged = helper.merge_config_string(profile);
        if (merged.status != "MERGE_SUCCESS" || merged.profileContent.empty() ||
            !merged.refPathList.empty())
            return reject();

        openvpn::ClientAPI::Config config;
        config.content = merged.profileContent;
        const auto result = helper.eval_config(config);
        if (result.error || result.remoteHost.empty()) return reject();
        // Do not echo any upstream messages, endpoint, username, or key.
        std::cout << "PARSED"
                  << " auth=" << (result.autologin ? "auto" : "interactive")
                  << " external_pki=" << (result.externalPki ? "yes" : "no")
                  << " key_password=" << (result.privateKeyPasswordRequired ? "yes" : "no")
                  << " challenge=" << (result.staticChallenge.empty() ? "no" : "yes")
                  << '\n';
        return 0;
    } catch (...) {
        return reject();
    }
}
