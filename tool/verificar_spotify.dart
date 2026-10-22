import 'dart:io';

import '../lib/music_match.dart';
import '../lib/spotify_client.dart';
import '../lib/user_messages.dart';

Future<void> main() async {
  var checks = 0;
  void check(bool value, String label) {
    if (!value) throw StateError(label);
    checks++;
  }

  const id = '1234567890123456789012';
  check(
    parseSpotify('https://open.spotify.com/intl-es/track/$id?si=test').id == id,
    'URL regional',
  );
  check(
    parseSpotify('spotify:playlist:$id').kind == 'playlist',
    'URI playlist',
  );
  for (final link in [
    'https://evil.com/track/$id',
    'https://open.spotify.com/album/$id',
    'https://evil@open.spotify.com/track/$id',
  ]) {
    var rejected = false;
    try {
      parseSpotify(link);
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Enlace inválido');
  }
  final song = SpotifySong(id, 'Canción del mar', ['Artista Uno'], 180000);
  final videos = rankMatches(song, [
    VideoMatch('cover______', 'Artista Uno Canción del mar cover', 'Otro', 180),
    VideoMatch('wrong______', 'Otra canción', 'Otro', 180),
    VideoMatch(
      'right______',
      'Artista Uno - Canción del mar (Official Audio)',
      'Artista Uno - Topic',
      181,
    ),
    VideoMatch(
      'live_______',
      'Artista Uno Canción del mar live',
      'Artista Uno',
      180,
    ),
  ]);
  check(
    videos.first.id == 'right______' && videos.first.confident,
    'Coincidencia correcta',
  );
  check(
    !videos.firstWhere((v) => v.id == 'cover______').confident,
    'Descartar cover',
  );
  check(
    !videos.firstWhere((v) => v.id == 'live_______').confident,
    'Descartar directo',
  );
  check(
    !rankMatches(song, [
      VideoMatch(
        'unknown____',
        'Artista Uno Canción del mar',
        'Artista Uno',
        0,
      ),
    ]).first.confident,
    'Duración desconocida requiere revisión',
  );
  check(
    !rankMatches(song, [
      VideoMatch(
        'long_______',
        'Artista Uno Canción del mar',
        'Artista Uno',
        600,
      ),
    ]).first.confident,
    'Duración diferente',
  );
  Map<String, dynamic> track(String name) => {
    'type': 'track',
    'id': id,
    'name': name,
    'artists': [
      {'name': 'Artista Uno'},
    ],
    'duration_ms': 180000,
  };
  var requests = 0;
  final collection = await readSpotifyCollection(
    'https://open.spotify.com/playlist/$id',
    (url) async {
      requests++;
      if (requests == 1)
        return {
          'name': 'Mi lista',
          'items': {
            'items': [
              {'item': track('Uno')},
              {'item': null},
            ],
            'next': 'https://api.spotify.com/v1/playlists/$id/items?offset=2',
          },
        };
      return {
        'items': [
          {'item': track('Dos')},
          {
            'item': {'type': 'episode', 'id': id},
          },
        ],
        'next': null,
      };
    },
    (_) {},
  );
  check(
    requests == 2 &&
        collection.songs.map((s) => s.title).join(',') == 'Uno,Dos',
    'Todas las páginas en orden',
  );
  check(collection.skipped == 2, 'Elementos no disponibles');
  final legacy = await readSpotifyCollection(
    'spotify:playlist:$id',
    (_) async => {
      'name': 'Antigua',
      'tracks': {
        'items': [
          {'track': track('Vieja')},
        ],
        'next': null,
      },
    },
    (_) {},
  );
  check(legacy.songs.single.title == 'Vieja', 'Campos API anterior');
  var failed = false;
  try {
    await readSpotifyCollection(
      'spotify:playlist:$id',
      (_) async => {
        'items': {
          'items': [
            {'item': track('Uno')},
          ],
          'next': 'https://evil.com/v1/playlists/$id/items',
        },
      },
      (_) {},
    );
  } on SpotifyProblem {
    failed = true;
  }
  check(failed, 'No enviar sesión a otra dirección');
  requests = 0;
  failed = false;
  try {
    await readSpotifyCollection('spotify:playlist:$id', (_) async {
      if (++requests == 1)
        return {
          'items': {
            'items': [
              {'item': track('Uno')},
            ],
            'next': 'https://api.spotify.com/v1/playlists/$id/items?offset=1',
          },
        };
      throw SpotifyProblem('Sin acceso');
    }, (_) {});
  } on SpotifyProblem {
    failed = true;
  }
  check(failed, 'No presentar playlist incompleta como completa');
  check(
    friendlyProgress('[download] /data/user/0/archivo', percent: 20) ==
        'Descargando canción…',
    'Ocultar ruta',
  );
  check(
    friendlyProgress('[ExtractAudio] ruta larga', converting: true) ==
        'Convirtiendo a MP3…',
    'Conversión amigable',
  );
  check(
    !friendlyError('PlatformException HTTP 403 trace')
        .contains('PlatformException'),
    'Error amigable',
  );
  final client = SpotifyClient()..clientId = 'a' * 32;
  var denied = false;
  try {
    await client.connect((url) async {
      check(
        url.queryParameters['code_challenge_method'] == 'S256' &&
            url.queryParameters['code_challenge']!.length == 43,
        'PKCE',
      );
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      check(redirect.host == '127.0.0.1', 'Callback solo local');
      final http = HttpClient();
      try {
        final wrong = await (await http.getUrl(
          redirect.replace(
            queryParameters: {'state': 'incorrecto', 'code': 'no'},
          ),
        )).close();
        check(wrong.statusCode == 400, 'Rechazar state falso');
        await wrong.drain<void>();
        final response = await (await http.getUrl(
          redirect.replace(
            queryParameters: {
              'state': url.queryParameters['state']!,
              'error': 'access_denied',
            },
          ),
        )).close();
        await response.drain<void>();
      } finally {
        http.close(force: true);
      }
      return true;
    });
  } on SpotifyProblem {
    denied = true;
  }
  check(denied && !client.connected, 'Denegar autorización no crea sesión');
  client.cancel();
  print('$checks comprobaciones Spotify correctas.');
}
