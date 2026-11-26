import 'package:blackout_kit_mobile/services/github_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dio client;
  late GitHubService service;
  late List<Uri> requests;
  late String location;

  setUp(() {
    requests = [];
    location = '/next';
    client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri);
      expect(options.followRedirects, isFalse);
      final first = options.uri.path == '/start';
      handler.resolve(Response<String>(
        requestOptions: options,
        statusCode: first ? 302 : 200,
        headers: Headers.fromMap(first
            ? {
                'location': [location]
              }
            : {}),
        data: first ? '' : 'fixture content',
      ));
    }));
    service = GitHubService(client: client);
  });

  tearDown(() => client.close(force: true));

  test('reject cleartext or URL credentials before sending requests', () async {
    for (final url in [
      'http://fixture.example/start',
      'https://secret@fixture.example/start',
      'file:///tmp/fixture',
    ]) {
      expect(await service.fetchDirectUrl(url), isNull);
    }
    expect(requests, isEmpty);
  });

  test('HTTPS redirects work and cache successful content', () async {
    expect(await service.fetchDirectUrl('https://fixture.example/start'),
        'fixture content');
    expect(requests.map((uri) => uri.path), ['/start', '/next']);
    expect(await service.fetchDirectUrl('https://fixture.example/start'),
        'fixture content');
    expect(requests, hasLength(2));
  });

  test('redirect downgrades and credentials are never requested', () async {
    for (final redirect in [
      'http://fixture.example/next',
      'https://secret@fixture.example/next',
    ]) {
      location = redirect;
      requests.clear();
      expect(await service.fetchDirectUrl('https://fixture.example/start'),
          isNull);
      expect(requests, hasLength(1));
    }
  });

  test('redirect loops stop after five redirects', () async {
    location = '/start';
    expect(
        await service.fetchDirectUrl('https://fixture.example/start'), isNull);
    expect(requests, hasLength(6));
  });
}
