/// Parse OpenVPN profile metadata without executing imported directives.
/// Runtime admission is deliberately narrower than the import format.
class OpenVpnProfile {
  final String host;
  final int port;
  final List<String> directives;
  final Set<String> inlineBlocks;

  const OpenVpnProfile._(
      this.host, this.port, this.directives, this.inlineBlocks);

  /// Detect standard encrypted PEM formats within the inline key block.
  static bool needsKeyPassword(String text) {
    final key = RegExp(r'<key>\s*([\s\S]*?)</key>').firstMatch(text)?.group(1);
    return key != null &&
        (key.contains('-----BEGIN ENCRYPTED PRIVATE KEY-----') ||
            key.contains('Proc-Type: 4,ENCRYPTED'));
  }

  static OpenVpnProfile? parse(String text) {
    if (text.length > 1024 * 1024 || text.contains('\u0000')) return null;
    String? block;
    var connection = false;
    String? host;
    int? remotePort;
    var defaultPort = 1194;
    final directives = <String>[];
    final blocks = <String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final tag = RegExp(r'^<(/?)([A-Za-z0-9_-]+)>$').firstMatch(line);
      if (block != null) {
        if (tag != null && tag[1] == '/' && tag[2] == block) block = null;
        continue;
      }
      if (tag != null) {
        if (tag[2] == 'connection') {
          if ((tag[1] == '/') != connection) return null;
          connection = !connection;
          continue;
        }
        if (tag[1] == '/') return null;
        block = tag[2]!;
        blocks.add(block);
        continue;
      }
      final words = _tokens(line);
      if (words == null || words.isEmpty) return null;
      final key = words.first.replaceFirst(RegExp(r'^--'), '').toLowerCase();
      directives.add(key);
      if (key == 'port' || key == 'rport') {
        if (words.length != 2) return null;
        final value = int.tryParse(words[1]);
        if (value == null || value < 1 || value > 65535) return null;
        defaultPort = value;
      }
      if (key == 'remote') {
        if (words.length < 2 || words.length > 4) return null;
        final endpoint = words[1];
        if (endpoint.isEmpty ||
            !RegExp(r'^[A-Za-z0-9._:\[\]-]+$').hasMatch(endpoint)) return null;
        final value = words.length >= 3 ? int.tryParse(words[2]) : null;
        if (words.length >= 3 &&
            (value == null || value < 1 || value > 65535)) {
          return null;
        }
        if (host == null) {
          host = endpoint;
          remotePort = value;
        }
      }
    }
    if (block != null || connection || host == null) return null;
    return OpenVpnProfile._(host, remotePort ?? defaultPort,
        List.unmodifiable(directives), Set.unmodifiable(blocks));
  }

  /// Initial runtime admission contract. Import is intentionally broader.
  /// No filesystem references, scripts, plugin loading, proxy credentials in
  /// files, or unknown directives are passed to an embedded client.
  static bool admitsRuntime(String text) {
    final profile = parse(text);
    if (profile == null) return false;
    const inline = {
      'ca',
      'cert',
      'key',
      'tls-auth',
      'tls-crypt',
      'tls-crypt-v2'
    };
    const permitted = {
      'client',
      'tls-client',
      'dev',
      'dev-type',
      'proto',
      'remote',
      'port',
      'rport',
      'remote-random',
      'remote-random-hostname',
      'resolv-retry',
      'nobind',
      'persist-key',
      'persist-tun',
      'auth',
      'cipher',
      'data-ciphers',
      'data-ciphers-fallback',
      'auth-nocache',
      'auth-user-pass',
      'remote-cert-tls',
      'verify-x509-name',
      'peer-fingerprint',
      'tls-version-min',
      'tls-version-max',
      'tls-cipher',
      'tls-ciphersuites',
      'key-direction',
      'verb',
      'mute',
      'connect-retry',
      'connect-retry-max',
      'connect-timeout',
      'ping',
      'ping-restart',
      'keepalive',
      'tun-mtu',
      'mssfix',
      'pull',
      'redirect-gateway',
      'route',
      'route-ipv6',
      'route-metric',
      'dhcp-option',
      'block-ipv6',
      'float',
      'explicit-exit-notify',
      'reneg-sec',
    };
    String? block;
    var inConnection = false;
    var hasContent = false;
    var tun = false;
    var peerVerification = false;
    var exactIdentity = false;
    var pinnedPeer = false;
    final seen = <String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final tag = RegExp(r'^<(/?)([A-Za-z0-9_-]+)>$').firstMatch(line);
      if (block != null) {
        if (tag != null) {
          if (tag[1] != '/' || tag[2] != block || !hasContent) return false;
          block = null;
        } else {
          hasContent = true;
        }
        continue;
      }
      if (tag != null) {
        if (tag[2] == 'connection') {
          inConnection = tag[1] != '/';
          continue;
        }
        if (inConnection) return false;
        final name = tag[2]!;
        if (tag[1] == '/' || !inline.contains(name) || !seen.add(name)) {
          return false;
        }
        block = name;
        hasContent = false;
        continue;
      }
      final words = _tokens(line);
      if (words == null || words.isEmpty || !permitted.contains(words.first)) {
        return false;
      }
      final key = words.first;
      if (inConnection &&
          !const {
            'remote',
            'proto',
            'port',
            'rport',
            'connect-retry',
            'connect-retry-max',
            'connect-timeout',
            'nobind',
          }.contains(key)) {
        return false;
      }
      if (key == 'dev' || key == 'dev-type') {
        if (words.length != 2 || words[1] != 'tun') return false;
        tun = true;
      }
      if (key == 'auth-user-pass' && words.length != 1) return false;
      if (key == 'remote-cert-tls') {
        if (words.length != 2 || words[1] != 'server') return false;
        peerVerification = true;
      }
      if (key == 'verify-x509-name') {
        if (exactIdentity || words.length < 2 || words.length > 3 ||
            words[1].isEmpty ||
            (words.length == 3 && !{'name', 'subject'}.contains(words[2]))) {
          return false;
        }
        exactIdentity = true;
      }
      if (key == 'peer-fingerprint') {
        if (words.length != 2 ||
            !RegExp(r'^(?:[A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$')
                .hasMatch(words[1])) {
          return false;
        }
        pinnedPeer = true;
      }
    }
    return tun && exactIdentity && peerVerification && seen.contains('ca') && !pinnedPeer;
  }

  static List<String>? _tokens(String line) {
    final result = <String>[];
    var word = StringBuffer();
    String? quote;
    var escaped = false;
    var present = false;
    void flush() {
      if (present) {
        result.add(word.toString());
        word = StringBuffer();
        present = false;
      }
    }

    for (final c in line.split('')) {
      if (escaped) {
        word.write(c);
        present = true;
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (quote != null) {
        if (c == quote) {
          quote = null;
        } else {
          word.write(c);
        }
      } else if (c == '"' || c == "'") {
        quote = c;
        present = true;
      } else if ((c == '#' || c == ';') && !present) {
        break;
      } else if (c.trim().isEmpty) {
        flush();
      } else {
        word.write(c);
        present = true;
      }
    }
    if (escaped || quote != null) return null;
    flush();
    return result;
  }
}
