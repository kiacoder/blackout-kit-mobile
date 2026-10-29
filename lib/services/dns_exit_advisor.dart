/// Warns when the chosen resolver does not match where the tunnel exits.
///
/// ## Why this exists
///
/// The resolver catalogue is split between **global** resolvers (Cloudflare,
/// Google, Quad9…) and **national** ones (Shecan, Radar, Electro, Begzar,
/// 403.online for Iran; Alibaba, Tencent, 114DNS for China). The national ones
/// are the right answer when you are *not* tunnelling — they are the whole
/// reason they exist, because the local ISP filters the global ones.
///
/// Inside a tunnel that exits elsewhere they are actively wrong:
///
/// 1. **Geo-DNS mismatch.** A national resolver returns answers tailored to its
///    own country. Resolve `google.com` through Shecan while exiting in
///    Germany and you get Iranian CDN nodes: the request travels through
///    Germany to reach an Iranian IP, and Google's edge sees a German client
///    asking for a page it would not normally serve there. Slower *and* a
///    location contradiction.
/// 2. **EDNS Client Subnet.** Resolvers may forward a truncated client subnet
///    to authoritative servers (RFC 7871) so CDNs can geo-target. Whose subnet
///    gets forwarded depends on where the query originates — so a resolver
///    chosen for the *home* country can still describe the home network while
///    the traffic exits abroad.
///
/// Neither problem is fatal on its own, but both push a session towards
/// "everything loads, just badly, and Google keeps asking me to prove I am
/// human". This advisor only *suggests*; it never changes the user's choice
/// behind their back.
library;

import '../models/dns_provider.dart';

/// A detected mismatch, with the resolver to switch to.
class DnsSuggestion {
  /// The resolver currently selected.
  final String providerKey;

  /// The country that resolver is tied to (ISO-3166 alpha-2).
  final String resolverCountry;

  /// Where the tunnel actually exits (ISO-3166 alpha-2).
  final String exitCountry;

  /// The global resolver to offer instead.
  final String suggestedKey;

  const DnsSuggestion({
    required this.providerKey,
    required this.resolverCountry,
    required this.exitCountry,
    this.suggestedKey = 'cloudflare',
  });

  /// Short headline for a list tile.
  String get title => 'Resolver does not match your exit';

  /// One-paragraph explanation, naming both countries.
  String get message =>
      '${_name(providerKey)} is a $resolverCountry resolver, but this tunnel '
      'exits in $exitCountry. Answers will be geo-mismatched (slower, and the '
      'destination sees a location contradiction). A global resolver such as '
      '${_name(suggestedKey)} matches the exit instead.';

  static String _name(String key) =>
      DnsCatalog.byKey(key)?.localizedName ?? key;

  @override
  String toString() =>
      'DnsSuggestion($providerKey[$resolverCountry] -> exit $exitCountry)';
}

class DnsExitAdvisor {
  const DnsExitAdvisor._();

  /// Returns a suggestion when [providerKey] is tied to a country other than
  /// [exitCountryCode], or null when the choice is fine.
  ///
  /// Unknown/empty inputs return null: without a known exit there is nothing
  /// to compare against, and guessing would produce noise in the UI.
  static DnsSuggestion? evaluate({
    required String providerKey,
    required String exitCountryCode,
  }) {
    final exit = exitCountryCode.trim().toUpperCase();
    if (exit.isEmpty) return null;
    if (DnsCatalog.byKey(providerKey) == null) return null;

    final resolverCountry = DnsCatalog.countryOf(providerKey);
    if (resolverCountry.isEmpty) return null; // already global
    if (resolverCountry == exit) return null; // matches the exit

    return DnsSuggestion(
      providerKey: providerKey,
      resolverCountry: resolverCountry,
      exitCountry: exit,
    );
  }

  /// True when the selected resolver is national and the tunnel exits in the
  /// same country — the case the catalogue is actually designed for.
  static bool isLocalMatch({
    required String providerKey,
    required String exitCountryCode,
  }) {
    final exit = exitCountryCode.trim().toUpperCase();
    if (exit.isEmpty) return false;
    return DnsCatalog.countryOf(providerKey) == exit;
  }
}
