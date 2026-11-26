import 'dart:convert';
import '../models/config.dart';

/// Portable batch exports, not engine conversion or connectivity validation.
/// JSON is a raw-profile array understood by ConfigParser.parseMultiple.
class ProfileExport {
  final String content;
  final int included;
  final int omitted;
  const ProfileExport(this.content, this.included, this.omitted);
}

class ProfileExportService {
  static const maxBytes = 8 * 1024 * 1024;

  static ProfileExport build(Iterable<Config> profiles, {bool v2rayN = false}) {
    final raw = <String>{};
    var omitted = 0;
    for (final profile in profiles) {
      final text = ConfigParser.normalizeScheme(profile.rawUri.trim());
      final scheme = text.split('://').first;
      // Conservative share-link intersection, NOT a promise that every
      // v2rayN version supports every transport/cipher in these links.
      if (v2rayN &&
          (!const {'vless', 'vmess', 'trojan', 'ss'}.contains(scheme) ||
              text.contains('\n') || text.contains('\r'))) {
        omitted++;
        continue;
      }
      if (text.isNotEmpty) raw.add(text);
    }
    final content = v2rayN
        ? raw.join('\n')
        : const JsonEncoder.withIndent('  ').convert(raw.toList());
    if (utf8.encode(content).length > maxBytes) {
      throw const FormatException('Export exceeds 8 MiB; export a smaller selection.');
    }
    return ProfileExport(content, raw.length, omitted);
  }
}
