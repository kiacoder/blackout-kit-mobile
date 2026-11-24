import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';

final secret = base64.encode(List<int>.filled(32, 251));
final peerKey = base64.encode(List<int>.filled(32, 2));
String profile([Map<String,String> extra = const {}]) =>
    'wireguard://${Uri.encodeComponent(secret)}@vpn.example.com:51820?'
    '${Uri(queryParameters: {'address':'10.88.0.2/32','publickey':peerKey,
        'mtu':'1420',...extra}).query}#Example';

String endpointJson({List<int>? reserved}) => jsonEncode({
  'endpoints': [{
    'type':'wireguard','tag':'Example','address':['10.88.0.2/32'],
    'private_key':secret,
    'peers':[{'address':'vpn.example.com','port':51820,'public_key':peerKey,
      'allowed_ips':['0.0.0.0/0','::/0'], if(reserved != null) 'reserved':reserved}]
  }],
  'outbounds': [], 'route': {'final':'ignore'}
});

class FakeGitHub extends GitHubService {
  final String? body;
  final calls = <String>[];
  FakeGitHub(this.body);
  @override
  Future<String?> fetchRawFile(String owner,String repo,String path,{String branch='main'}) async {
    calls.add(path);
    return body;
  }
}

void main() {
  test('WireGuard share links become native conf and preserve keys', () {
    final config = ConfigParser.parse(profile()) as WireGuardConfig;
    expect(config.validate(), isTrue);
    expect(config.privateKey, secret);
    expect(config.rawUri, contains('[Interface]'));
    expect(config.peers.single.publicKey, peerKey);
    expect(config.address, 'vpn.example.com');
    expect(ConfigParser.parseMultiple(profile()).single.protocol, 'wireguard');
  });
  test('WireGuard links with AWG fields retain them and select AWG', () {
    final config = ConfigParser.parse(profile({'jc':'4','jmin':'40','jmax':'70','h1':'100-200'}));
    expect(config, isA<AmneziaWGConfig>());
    expect(config!.rawUri, contains('H1 = 100-200'));
  });
  test('unsupported fields, malformed keys and config injection are refused', () {
    for (final extra in [
      {'reserved':'1,2,3'}, {'ifp':'some-extension'}, {'wnoise':'1'},
      {'publickey':'bad'}, {'dns':'1.1.1.1\nPostUp=bad'},
      {'jc':'bad'}, {'h1':'300-100'},
    ]) {
      expect(ConfigParser.parse(profile(extra)), isNull);
    }
  });
  test('sing-box endpoints convert without importing arbitrary routing', () {
    final configs = ConfigParser.parseWireGuardEndpointDocument(endpointJson());
    expect(configs, hasLength(1));
    expect((configs.single as WireGuardConfig).privateKey, secret);
    expect(configs.single.rawUri, isNot(contains('ignore')));
    expect(ConfigParser.parseWireGuardEndpointDocument(endpointJson(reserved:[1,2,3])), isEmpty);
  });
  test('community sources are listed but opt-in and never guess unrelated files', () async {
    final sources = TrustedSources.sources.where((s) => s.id.startsWith('community-')).toList();
    expect(sources, hasLength(2));
    expect(sources.every((s) => !s.isEnabled), isTrue);
    for (final source in sources) {
      final fake = FakeGitHub(source.id.contains('au1rxx') ? endpointJson() : profile());
      expect(await fake.fetchConfigsFromSource(source), hasLength(1));
      expect(fake.calls, [source.filePath]);
      final missing = FakeGitHub(null);
      await expectLater(missing.fetchConfigsFromSource(source), throwsA(isA<SourceUnavailableException>()));
      expect(missing.calls, [source.filePath]);
    }
  });
}
