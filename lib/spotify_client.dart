import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'music_match.dart';

class SpotifyProblem implements Exception {
  final String message;
  SpotifyProblem(this.message);
  @override
  String toString() => message;
}

class SpotifyCollection {
  final String name;
  final List<SpotifySong> songs;
  final int skipped;
  final bool playlist;
  SpotifyCollection(this.name, this.songs, this.skipped, this.playlist);
}

class SpotifyClient {
  static const redirectRegistration = 'http://127.0.0.1:8888/callback';
  final Future<String?> Function()? readSession;
  final Future<void> Function(String?)? writeSession;
  final HttpClient Function() _httpFactory;
  SpotifyClient({
    this.readSession,
    this.writeSession,
    HttpClient Function()? httpFactory,
  }) : _httpFactory = httpFactory ?? HttpClient.new;
  String sessionNotice = '';
  String clientId = '';
  String? _access, _refresh;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);
  HttpClient? _http;
  HttpServer? _server;
  Completer<String>? _authorization;
  bool get connected => _access != null || _refresh != null;
  Future<void> disconnect() async {
    _access = null;
    _refresh = null;
    await writeSession?.call(null);
  }

  void cancel() {
    _http?.close(force: true);
    _http = null;
    final waiter = _authorization;
    if (waiter != null && !waiter.isCompleted)
      waiter.completeError(SpotifyProblem('Conexión cancelada.'));
    unawaited(_server?.close(force: true));
  }

  String _random(int count) => base64Url
      .encode(List.generate(count, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  void _begin() {
    _http?.close(force: true);
    _http = _httpFactory()..connectionTimeout = const Duration(seconds: 20);
  }

  Future<void> configure(String id, File config) async {
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(id.trim()))
      throw SpotifyProblem(
        'El Client ID debe tener 32 caracteres. No uses el Client Secret.',
      );
    if (clientId != id.trim()) await disconnect();
    clientId = id.trim();
    await config.writeAsString(jsonEncode({'clientId': clientId}), flush: true);
  }

  Future<void> load(File config, {String embeddedClientId = ''}) async {
    if (await config.exists()) {
      try {
        clientId =
            (jsonDecode(await config.readAsString()) as Map)['clientId']
                as String? ??
            '';
      } catch (_) {}
    }
    if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(embeddedClientId)) {
      clientId = embeddedClientId;
    }
    try {
      final raw = await readSession?.call();
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        if (data['clientId'] == clientId &&
            data['refreshToken'] is String &&
            (data['refreshToken'] as String).isNotEmpty) {
          _refresh = data['refreshToken'] as String;
        } else {
          await writeSession?.call(null);
        }
      }
    } catch (_) {
      sessionNotice =
          'No se pudo recuperar la sesión. Conecta Spotify de nuevo.';
    }
  }

  Future<void> connect(Future<bool> Function(Uri) openBrowser) async {
    if (clientId.isEmpty)
      throw SpotifyProblem(
        'Primero introduce el Client ID de tu aplicación de Spotify.',
      );
    _begin();
    final verifier = _random(64);
    final state = _random(32);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    late HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
    } on SocketException {
      throw SpotifyProblem(
        'No se pudo abrir la conexión local. Cierra otras sesiones de Ritmo e inténtalo de nuevo.',
      );
    }
    _server = server;
    const redirect = redirectRegistration;
    final code = Completer<String>();
    _authorization = code;
    // Attach the error handler before the browser or cancel button can complete it.
    final codeFuture = code.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw SpotifyProblem(
        'Se agotó el tiempo para conectar. Inténtalo de nuevo.',
      ),
    );
    unawaited(
      codeFuture.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    server.listen((request) async {
      if (request.uri.path != '/callback' ||
          request.uri.queryParameters['state'] != state) {
        request.response.statusCode = 400;
        request.response.write('Solicitud no válida.');
        await request.response.close();
        return;
      }
      final value = request.uri.queryParameters['code'];
      final denied =
          request.uri.queryParameters.containsKey('error') || value == null;
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(
        '<!doctype html><meta name="viewport" content="width=device-width"><title>Ritmo</title><body style="background:#110e17;color:white;font:20px sans-serif;padding:32px"><h1>Ritmo</h1><p>${denied ? "No se autorizó la conexión." : "Autorización recibida."}</p><p>Vuelve a Ritmo para continuar.</p></body>',
      );
      await request.response.close();
      if (!code.isCompleted) {
        if (denied) {
          code.completeError(
            SpotifyProblem('No se autorizó la conexión con Spotify.'),
          );
        } else {
          code.complete(value);
        }
      }
    });
    try {
      final authorize = Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirect,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        'scope': 'playlist-read-private playlist-read-collaborative',
      });
      var opened = false;
      try {
        opened = await openBrowser(authorize);
      } catch (_) {}
      if (!opened) {
        if (!code.isCompleted)
          code.completeError(SpotifyProblem('No se pudo abrir el navegador.'));
      }
      final granted = await codeFuture;
      final data = await _request(
        Uri.https('accounts.spotify.com', '/api/token'),
        form: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': granted,
          'redirect_uri': redirect,
          'code_verifier': verifier,
        },
      );
      await _acceptToken(data);
    } finally {
      _authorization = null;
      _server = null;
      await server.close(force: true);
    }
  }

  Future<void> _acceptToken(Map<String, dynamic> data) async {
    final access = data['access_token'];
    if (access is! String || access.isEmpty)
      throw SpotifyProblem('Spotify no devolvió una sesión válida.');
    _access = access;
    _refresh = data['refresh_token'] as String? ?? _refresh;
    _expiry = DateTime.now().add(
      Duration(seconds: ((data['expires_in'] as num?)?.toInt() ?? 3600) - 60),
    );
    sessionNotice = '';
    try {
      await writeSession?.call(
        jsonEncode({'clientId': clientId, 'refreshToken': _refresh}),
      );
    } catch (_) {
      sessionNotice = 'Conectado, pero no se pudo guardar la sesión. Al reabrir tendrás que conectar de nuevo.';
    }
  }

  Future<void> _renew() async {
    if (_refresh == null)
      throw SpotifyProblem('Conecta tu cuenta de Spotify para continuar.');
    // Los fallos de red no deben borrar una autorización válida.
    await _acceptToken(
      await _request(
        Uri.https('accounts.spotify.com', '/api/token'),
        form: {
          'grant_type': 'refresh_token',
          'refresh_token': _refresh!,
          'client_id': clientId,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _request(
    Uri url, {
    Map<String, String>? form,
    bool retry401 = true,
  }) async {
    final api = url.host == 'api.spotify.com';
    if (url.scheme != 'https' ||
        (!api && url.host != 'accounts.spotify.com') ||
        url.userInfo.isNotEmpty)
      throw SpotifyProblem('Spotify devolvió una dirección no válida.');
    if (api && (_access == null || DateTime.now().isAfter(_expiry)))
      await _renew();
    final client = _http;
    if (client == null) throw SpotifyProblem('Operación cancelada.');
    final request =
        await (form == null ? client.getUrl(url) : client.postUrl(url)).timeout(
          const Duration(seconds: 25),
        );
    request.followRedirects = false;
    if (api) request.headers.set('Authorization', 'Bearer $_access');
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        form.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 25));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 && api && retry401) {
      await _renew();
      return _request(url, retry401: false);
    }
    if (!api && response.statusCode == 400) {
      Map<dynamic, dynamic> failure = {};
      try {
        failure = jsonDecode(body) as Map;
      } catch (_) {}
      if (failure['error'] == 'invalid_grant') {
        await disconnect();
        throw SpotifyProblem(
          'La autorización caducó o fue revocada. Conecta Spotify de nuevo.',
        );
      }
    }
    if (response.statusCode == 403)
      throw SpotifyProblem(
        'Spotify no permite leer este contenido. En modo desarrollo revisa Premium, usuarios autorizados y que la playlist sea tuya o colaborativa.',
      );
    if (response.statusCode == 429)
      throw SpotifyProblem(
        'Spotify pide esperar ${response.headers.value('retry-after') ?? "unos"} segundos. Vuelve a intentarlo después.',
      );
    if (response.statusCode == 404)
      throw SpotifyProblem(
        'Spotify no encontró la canción o playlist, o no permite acceder a ella.',
      );
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw SpotifyProblem(
        'No se pudo conectar con Spotify (${response.statusCode}). Revisa el Client ID y la configuración de tu app.',
      );
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }

  Future<SpotifyCollection> read(
    String input,
    void Function(int) progress,
  ) async {
    _begin();
    if (!connected)
      throw SpotifyProblem('Conecta tu cuenta de Spotify primero.');
    return readSpotifyCollection(input, (uri) => _request(uri), progress);
  }
}

Future<SpotifyCollection> readSpotifyCollection(
  String input,
  Future<Map<String, dynamic>> Function(Uri) fetch,
  void Function(int) progress,
) async {
  final source = parseSpotify(input);
  final root = await fetch(
    Uri.https(
      'api.spotify.com',
      '/v1/${source.kind == "track" ? "tracks" : "playlists"}/${source.id}',
    ),
  );
  final songs = <SpotifySong>[];
  var skipped = 0;
  void append(dynamic raw) {
    if (raw is! Map ||
        raw['type'] != 'track' ||
        raw['is_local'] == true ||
        raw['id'] is! String) {
      skipped++;
      return;
    }
    final artists = (raw['artists'] as List? ?? [])
        .whereType<Map>()
        .map((a) => a['name'] as String? ?? '')
        .where((a) => a.isNotEmpty)
        .toList();
    songs.add(
      SpotifySong(
        raw['id'] as String,
        raw['name'] as String? ?? 'Canción',
        artists,
        (raw['duration_ms'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  if (source.kind == 'track')
    append(root);
  else {
    Map<String, dynamic>? page;
    final embedded = root['items'] ?? root['tracks'];
    if (embedded is Map) page = Map<String, dynamic>.from(embedded);
    page ??= await fetch(
      Uri.https('api.spotify.com', '/v1/playlists/${source.id}/items', {
        'limit': '50',
      }),
    );
    final visited = <String>{};
    while (true) {
      for (final raw in page!['items'] as List? ?? []) {
        if (raw is Map) {
          append(raw['item'] ?? raw['track']);
        } else {
          skipped++;
        }
      }
      progress(songs.length);
      final next = page['next'] as String?;
      if (next == null) break;
      final uri = Uri.parse(next);
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.host != 'api.spotify.com' ||
          !uri.path.startsWith('/v1/playlists/${source.id}/') ||
          !visited.add(next))
        throw SpotifyProblem('No se pudo continuar leyendo la playlist.');
      page = await fetch(uri);
    }
  }
  if (songs.isEmpty)
    throw SpotifyProblem(
      'No hay canciones disponibles para importar en este enlace.',
    );
  return SpotifyCollection(
    root['name'] as String? ?? songs.first.title,
    songs,
    skipped,
    source.kind == 'playlist',
  );
}
