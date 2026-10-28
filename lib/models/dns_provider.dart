/// DNS resolver catalogue.
///
/// The `sanctions` and `speed` groups are XDNS's own lists — the exact
/// primary/secondary pairs that single-file Windows client switches between.
/// They are reproduced here (and in the desktop CLI's
/// `blackoutkit/dns_engine.py`) because they are known-good pairs for the
/// networks this app targets. In particular the Iranian resolvers are used as
/// *pairs*: keeping only the primary address throws away the redundancy the
/// operator intended.
///
/// A provider is a pair, not an address. [DnsProvider.servers] always returns
/// the primary first so `VpnService.Builder.addDnsServer` sees them in the
/// order the OS should try them.
library;

enum DnsCategory { sanctions, speed, extra }

class DnsProvider {
  final String key;
  final String name;
  final String primary;
  final String? secondary;
  final DnsCategory category;
  final String note;

  const DnsProvider({
    required this.key,
    required this.name,
    required this.primary,
    required this.category,
    this.secondary,
    this.note = '',
  });

  /// Primary first, then secondary — the order the tunnel should advertise.
  List<String> get servers =>
      secondary == null ? [primary] : [primary, secondary!];

  String get label => secondary == null ? name : '$name ($primary, $secondary)';

  String get shortLabel => '$name — $primary${secondary == null ? '' : ', $secondary'}';

  bool matches(List<String> current) =>
      current.isNotEmpty && current.first == primary;

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'primary': primary,
        'secondary': secondary,
        'category': category.name,
        'note': note,
      };
}

/// The catalogue itself. Ordered as it should be displayed.
class DnsCatalog {
  const DnsCatalog._();

  static const Map<DnsCategory, String> categoryLabels = {
    DnsCategory.sanctions:
        'Sanctions — resolvers chosen to survive national filtering',
    DnsCategory.speed: 'Speed — high-performance public resolvers',
    DnsCategory.extra: 'Extra — filtering, privacy and domestic resolvers',
  };

  static const List<DnsProvider> all = [
    // -- Sanctions: survive filtering ------------------------------------
    DnsProvider(
      key: 'shecan',
      name: 'Shecan',
      primary: '178.22.122.100',
      secondary: '185.51.200.2',
      category: DnsCategory.sanctions,
      note: 'Iranian filtered-but-fast resolver',
    ),
    DnsProvider(
      key: 'electro',
      name: 'Electro',
      primary: '78.157.42.100',
      secondary: '78.157.42.101',
      category: DnsCategory.sanctions,
      note: 'Iranian bypass resolver',
    ),
    DnsProvider(
      key: 'begzar',
      name: 'Begzar',
      primary: '185.55.226.26',
      secondary: '185.55.226.25',
      category: DnsCategory.sanctions,
      note: 'Iranian unfiltered resolver',
    ),
    DnsProvider(
      key: 'radar',
      name: 'Radar',
      primary: '10.202.10.10',
      secondary: '10.202.10.11',
      category: DnsCategory.sanctions,
      note: 'Iranian game / anti-sanction resolver',
    ),
    DnsProvider(
      key: '403',
      name: '403.online',
      primary: '10.202.10.202',
      secondary: '10.202.10.102',
      category: DnsCategory.sanctions,
      note: 'Iranian anti-sanction resolver (403.online)',
    ),
    DnsProvider(
      key: 'opendns',
      name: 'OpenDNS',
      primary: '208.67.222.222',
      secondary: '208.67.220.220',
      category: DnsCategory.sanctions,
      note: 'Cisco OpenDNS — the fallback in XDNS\'s list',
    ),
    // -- Speed: public resolvers -----------------------------------------
    DnsProvider(
      key: 'yandex',
      name: 'Yandex',
      primary: '77.88.8.8',
      secondary: '77.88.8.1',
      category: DnsCategory.speed,
      note: 'Low latency from Iran and the CIS',
    ),
    DnsProvider(
      key: 'cloudflare',
      name: 'Cloudflare',
      primary: '1.1.1.1',
      secondary: '1.0.0.1',
      category: DnsCategory.speed,
      note: 'Fastest global anycast resolver',
    ),
    DnsProvider(
      key: 'cloudflare-security',
      name: 'Cloudflare Security',
      primary: '1.1.1.2',
      secondary: '1.0.0.2',
      category: DnsCategory.speed,
      note: 'Cloudflare with malware blocking',
    ),
    DnsProvider(
      key: 'cloudflare-family',
      name: 'Cloudflare Family',
      primary: '1.1.1.3',
      secondary: '1.0.0.3',
      category: DnsCategory.speed,
      note: 'Cloudflare with malware and adult-content blocking',
    ),
    DnsProvider(
      key: 'google',
      name: 'Google',
      primary: '8.8.8.8',
      secondary: '8.8.4.4',
      category: DnsCategory.speed,
      note: 'Widely reachable, heavily logged',
    ),
    DnsProvider(
      key: 'dnssb',
      name: 'DNS.SB',
      primary: '185.222.222.222',
      secondary: '45.11.45.11',
      category: DnsCategory.speed,
      note: 'No-log resolver with DoH / DoT / DoQ',
    ),
    DnsProvider(
      key: 'controld',
      name: 'Control D',
      primary: '76.76.2.0',
      secondary: '76.76.10.0',
      category: DnsCategory.speed,
      note: 'Free tier of Control D\'s filtering resolver',
    ),
    DnsProvider(
      key: 'level3',
      name: 'Level3',
      primary: '4.2.2.1',
      secondary: '4.2.2.2',
      category: DnsCategory.speed,
      note: 'Long-lived public resolver, good reachability',
    ),
    DnsProvider(
      key: 'vercara',
      name: 'Vercara (Neustar)',
      primary: '64.6.64.6',
      secondary: '64.6.65.6',
      category: DnsCategory.speed,
      note: 'Formerly Verisign / Neustar',
    ),
    DnsProvider(
      key: 'comodo',
      name: 'Comodo',
      primary: '8.26.56.26',
      secondary: '8.20.247.20',
      category: DnsCategory.speed,
      note: 'SecureDNS — older infrastructure, widely reachable',
    ),
    DnsProvider(
      key: 'gcore',
      name: 'Gcore',
      primary: '95.85.95.85',
      secondary: '2.56.220.2',
      category: DnsCategory.speed,
      note: 'Low latency in Europe and the CIS',
    ),
    DnsProvider(
      key: 'oracle',
      name: 'Oracle Dyn',
      primary: '216.146.35.35',
      secondary: '216.146.36.36',
      category: DnsCategory.speed,
      note: 'Oracle\'s long-running Dyn resolver',
    ),
    DnsProvider(
      key: 'wikimedia',
      name: 'Wikimedia',
      primary: '185.71.138.138',
      category: DnsCategory.speed,
      note: 'Non-profit resolver run by the Wikimedia Foundation',
    ),
    DnsProvider(
      key: 'dns4eu',
      name: 'DNS4EU',
      primary: '86.54.11.100',
      secondary: '86.54.11.200',
      category: DnsCategory.speed,
      note: 'EU-backed unfiltered resolver',
    ),
    // -- Extra: filtering, privacy, domestic ------------------------------
    DnsProvider(
      key: 'quad9',
      name: 'Quad9',
      primary: '9.9.9.9',
      secondary: '149.112.112.112',
      category: DnsCategory.extra,
      note: 'Blocks known-malicious domains',
    ),
    DnsProvider(
      key: 'quad9-unsecured',
      name: 'Quad9 Unfiltered',
      primary: '9.9.9.10',
      secondary: '149.112.112.10',
      category: DnsCategory.extra,
      note: 'Quad9 with the blocklist removed',
    ),
    DnsProvider(
      key: 'adguard',
      name: 'AdGuard',
      primary: '94.140.14.14',
      secondary: '94.140.15.15',
      category: DnsCategory.extra,
      note: 'Ad and tracker filtering',
    ),
    DnsProvider(
      key: 'adguard-family',
      name: 'AdGuard Family',
      primary: '94.140.14.15',
      secondary: '94.140.15.16',
      category: DnsCategory.extra,
      note: 'Ad filtering plus safe search and adult-content blocking',
    ),
    DnsProvider(
      key: 'adguard-nonfiltering',
      name: 'AdGuard Unfiltered',
      primary: '94.140.14.140',
      secondary: '94.140.14.141',
      category: DnsCategory.extra,
      note: 'AdGuard with no filtering at all',
    ),
    DnsProvider(
      key: 'cleanbrowsing',
      name: 'CleanBrowsing',
      primary: '185.228.168.9',
      secondary: '185.228.169.9',
      category: DnsCategory.extra,
      note: 'Blocks malware and phishing',
    ),
    DnsProvider(
      key: 'cleanbrowsing-family',
      name: 'CleanBrowsing Family',
      primary: '185.228.168.168',
      secondary: '185.228.169.168',
      category: DnsCategory.extra,
      note: 'Family filter: adult content, proxies and VPNs',
    ),
    DnsProvider(
      key: 'nextdns',
      name: 'NextDNS',
      primary: '45.90.28.0',
      secondary: '45.90.30.0',
      category: DnsCategory.extra,
      note: 'Configurable filtering; needs an account for profiles',
    ),
    DnsProvider(
      key: 'mullvad',
      name: 'Mullvad',
      primary: '194.242.2.2',
      secondary: '194.242.2.4',
      category: DnsCategory.extra,
      note: 'No-log, no-filter resolver (default + base endpoints)',
    ),
    DnsProvider(
      key: 'opendns-family',
      name: 'OpenDNS FamilyShield',
      primary: '208.67.222.123',
      secondary: '208.67.220.123',
      category: DnsCategory.extra,
      note: 'OpenDNS with adult content blocked',
    ),
    DnsProvider(
      key: 'yandex-safe',
      name: 'Yandex Safe',
      primary: '77.88.8.88',
      secondary: '77.88.8.2',
      category: DnsCategory.extra,
      note: 'Yandex with fraud and infected-site blocking',
    ),
    DnsProvider(
      key: 'yandex-family',
      name: 'Yandex Family',
      primary: '77.88.8.7',
      secondary: '77.88.8.3',
      category: DnsCategory.extra,
      note: 'Yandex with adult content blocked',
    ),
    DnsProvider(
      key: 'alibaba',
      name: 'Alibaba',
      primary: '223.5.5.5',
      secondary: '223.6.6.6',
      category: DnsCategory.extra,
      note: 'Domestic resolver inside the GFW',
    ),
    DnsProvider(
      key: 'tencent',
      name: 'Tencent',
      primary: '119.29.29.29',
      secondary: '182.254.116.116',
      category: DnsCategory.extra,
      note: 'Domestic resolver inside the GFW',
    ),
    DnsProvider(
      key: '114dns',
      name: '114DNS',
      primary: '114.114.114.114',
      secondary: '114.114.115.115',
      category: DnsCategory.extra,
      note: 'Domestic resolver inside the GFW',
    ),
  ];

  /// The fallback when nothing is selected — Cloudflare's pair.
  static const DnsProvider fallback = DnsProvider(
    key: 'cloudflare',
    name: 'Cloudflare',
    primary: '1.1.1.1',
    secondary: '1.0.0.1',
    category: DnsCategory.speed,
  );

  static List<DnsProvider> inCategory(DnsCategory category) =>
      all.where((p) => p.category == category).toList();

  static DnsProvider? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final provider in all) {
      if (provider.key == key) return provider;
    }
    return null;
  }

  static DnsProvider? byAddress(String address) {
    for (final provider in all) {
      if (provider.servers.contains(address)) return provider;
    }
    return null;
  }

  /// Which catalogue entry the current resolver list corresponds to.
  static DnsProvider? activeFor(List<String> servers) {
    if (servers.isEmpty) return null;
    return byAddress(servers.first);
  }

  /// Accepts a bare IPv4/IPv6 literal. Android's `addDnsServer` only takes
  /// literals, so anything else would be silently dropped by the OS.
  static bool isIpLiteral(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return false;
    if (raw.contains(':')) return true; // IPv6
    final parts = raw.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Splits `"1.1.1.1, 1.0.0.1"` into its IP literals, dropping the rest.
  static List<String> parseServers(String raw) => raw
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim())
      .where(isIpLiteral)
      .toList();
}
