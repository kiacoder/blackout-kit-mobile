import 'dart:convert';
import 'dart:typed_data';

const maxConfigImportBytes = 5 * 1024 * 1024;

class ConfigImportTooLarge implements Exception {
  const ConfigImportTooLarge();
}

/// Enforce the actual byte count, not metadata from a document provider.
/// A rejected stream is cancelled by the await-for loop.
Future<String> readBoundedConfigText(
  Stream<List<int>> source, {
  int maxBytes = maxConfigImportBytes,
}) async {
  if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  final bytes = BytesBuilder();
  await for (final chunk in source) {
    if (chunk.length > maxBytes - bytes.length) {
      throw const ConfigImportTooLarge();
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
