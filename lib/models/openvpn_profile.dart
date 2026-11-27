/// Parse OpenVPN profile metadata without executing imported directives.
/// Runtime admission is deliberately narrower than the import format.
class OpenVpnProfile {
  final String host;
  final int port;
  final List<String> directives;
  final Set<String> inlineBlocks;

  const OpenVpnProfile._(
      this.host, this.port, this.directives, this.inlineBlocks);

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

  static List<String>? _tokens(String line) {
    final result = <String>[];
    var word = StringBuffer();
    String? quote;
    var escaped = false;
    void flush() {
      if (word.isNotEmpty) {
        result.add(word.toString());
        word = StringBuffer();
      }
    }

    for (final c in line.split('')) {
      if (escaped) {
        word.write(c);
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
      } else if ((c == '#' || c == ';') && word.isEmpty) {
        break;
      } else if (c.trim().isEmpty) {
        flush();
      } else {
        word.write(c);
      }
    }
    if (escaped || quote != null) return null;
    flush();
    return result;
  }
}
