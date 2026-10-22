import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/spotify_client.dart';

// HTTP simulado: estas pruebas no envían credenciales ni contactan Spotify.
class FakeHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  String? value(String name) => values[name]?.toString();
  @override
  set contentType(ContentType? value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final Object body;
  @override
  final headers = FakeHeaders();
  FakeResponse(this.statusCode, this.body);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(body))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  final Future<HttpClientResponse> Function(FakeRequest) respond;
  final Uri url;
  final String method;
  String body = '';
  @override
  final headers = FakeHeaders();
  @override
  bool followRedirects = true;
  FakeRequest(this.url, this.method, this.respond);
  @override
  void write(Object? object) {
    body += '$object';
  }

  @override
  Future<HttpClientResponse> close() => respond(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClient implements HttpClient {
  final Future<HttpClientResponse> Function(FakeRequest) respond;
  FakeClient(this.respond);
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      FakeRequest(url, 'GET', respond);
  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      FakeRequest(url, 'POST', respond);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  var count = 0;
  void check(bool ok, String why) {
    if (!ok) throw StateError(why);
    count++;
  }

  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const trackId = '1234567890123456789012';
  final dir = await Directory.systemTemp.createTemp('ritmo_session_test');
  final config = File('${dir.path}/spotify-config.json');
  String? disk;
  var tokenCalls = 0;
  var mode = 'ok';
  var rotate = true;
  var unauthorizedOnce = false;
  Future<HttpClientResponse> respond(FakeRequest request) async {
    if (request.url.host == 'accounts.spotify.com') {
      tokenCalls++;
      final form = Uri.splitQueryString(request.body);
      check(
        form['client_id'] == id && !form.containsKey('client_secret'),
        'PKCE no usa secreto',
      );
      check(
        !request.followRedirects,
        'No reenviar credenciales por redirección',
      );
      if (mode == 'offline') throw const SocketException('Sin red');
      if (mode == 'revoked')
        return FakeResponse(400, {'error': 'invalid_grant'});
      if (mode == 'busy')
        return FakeResponse(503, {'error': 'temporarily_unavailable'});
      return FakeResponse(200, {
        'access_token': 'test-access',
        'expires_in': 3600,
        if (rotate) 'refresh_token': 'rotated-token',
      });
    }
    check(
      request.headers.value('Authorization') == 'Bearer test-access',
      'Acceso renovado',
    );
    if (unauthorizedOnce) {
      unauthorizedOnce = false;
      return FakeResponse(401, {});
    }
    return FakeResponse(200, {
      'type': 'track',
      'id': trackId,
      'name': 'Prueba',
      'artists': [
        {'name': 'Artista'},
      ],
      'duration_ms': 100000,
    });
  }

  SpotifyClient make() => SpotifyClient(
    readSession: () async => disk,
    writeSession: (value) async {
      disk = value;
    },
    httpFactory: () => FakeClient(respond),
  );
  try {
    var client = make();
    await client.load(config, embeddedClientId: id);
    check(
      client.clientId == id && !client.connected,
      'ID incorporado sin sesión inventada',
    );
    disk = jsonEncode({'clientId': id, 'refreshToken': 'old-token'});
    client = make();
    await client.load(config, embeddedClientId: id);
    check(client.connected, 'Recuperar sesión al reiniciar');
    final song = await client.read('spotify:track:$trackId', (_) {});
    check(
      song.songs.single.title == 'Prueba' && tokenCalls == 1,
      'Renovar sin navegador',
    );
    check(
      (jsonDecode(disk!) as Map)['refreshToken'] == 'rotated-token',
      'Persistir rotación',
    );
    check(!disk!.contains('test-access'), 'No persistir token de acceso');
    await client.read('spotify:track:$trackId', (_) {});
    check(tokenCalls == 1, 'Reutilizar token vigente');
    unauthorizedOnce = true;
    await client.read('spotify:track:$trackId', (_) {});
    check(tokenCalls == 2, 'Renovar una vez tras 401');
    rotate = false;
    client = make();
    await client.load(config, embeddedClientId: id);
    await client.read('spotify:track:$trackId', (_) {});
    check(
      (jsonDecode(disk!) as Map)['refreshToken'] == 'rotated-token',
      'Conservar refresh cuando respuesta no lo incluye',
    );
    for (final failure in ['offline', 'busy']) {
      mode = failure;
      client = make();
      await client.load(config, embeddedClientId: id);
      var failed = false;
      try {
        await client.read('spotify:track:$trackId', (_) {});
      } catch (_) {
        failed = true;
      }
      check(
        failed && client.connected && disk != null,
        'Conservar sesión ante $failure',
      );
    }
    mode = 'revoked';
    client = make();
    await client.load(config, embeddedClientId: id);
    try {
      await client.read('spotify:track:$trackId', (_) {});
    } on SpotifyProblem catch (_) {}
    check(!client.connected && disk == null, 'Borrar sesión revocada');
    disk = jsonEncode({'clientId': id, 'refreshToken': 'test'});
    client = make();
    await client.load(config, embeddedClientId: 'b' * 32);
    check(
      !client.connected && disk == null,
      'No reutilizar sesión con otro ID',
    );
    disk = jsonEncode({'clientId': id, 'refreshToken': 'test'});
    client = make();
    await client.load(config, embeddedClientId: id);
    await client.disconnect();
    check(
      !client.connected && disk == null,
      'Desconectar borra almacenamiento',
    );
    disk = 'json dañado';
    client = make();
    await client.load(config, embeddedClientId: id);
    check(
      !client.connected && client.sessionNotice.isNotEmpty,
      'Almacenamiento dañado no impide abrir app',
    );
    client = make();
    await client.load(config, embeddedClientId: id);
    var canceled = false;
    try {
      await client.connect((url) async {
        check(
          url.queryParameters['redirect_uri'] ==
              SpotifyClient.redirectRegistration,
          'Retorno coincide exactamente con registro',
        );
        client.cancel();
        return true;
      });
    } on SpotifyProblem {
      canceled = true;
    }
    check(
      canceled && !client.connected,
      'Cancelar autorización no crea sesión',
    );
    mode = 'ok';
    rotate = true;
    disk = null;
    client = make();
    await client.load(config, embeddedClientId: id);
    await client.connect((url) async {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      final browser = HttpClient();
      try {
        final response = await (await browser.getUrl(redirect.replace(queryParameters: {
          'state': url.queryParameters['state']!, 'code': 'test-authorization-code',
        }))).close();
        await response.drain<void>();
      } finally { browser.close(force: true); }
      return true;
    });
    check(client.connected && disk != null, 'Autorización inicial persiste sesión');
    final reopened = make();
    await reopened.load(config, embeddedClientId: id);
    check(reopened.connected, 'Sesión inicial recuperada en nueva instancia');
    await reopened.disconnect();
    // El puerto debe quedar libre tras cancelar.
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
    check(listener.port == 8888, 'Liberar puerto al cancelar');
    await listener.close(force: true);
    client.cancel();
  } finally {
    await dir.delete(recursive: true);
  }
  print('$count comprobaciones de sesión correctas.');
}
