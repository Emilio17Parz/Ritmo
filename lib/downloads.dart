import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'links.dart';
import 'models.dart';
import 'transfer.dart';
import 'spotify_client.dart';
import 'spotify_storage.dart';
import 'spotify_build_config.dart';
import 'music_match.dart';
import 'user_messages.dart';
export 'models.dart';

const native = MethodChannel('nube_music/files');

class Downloads extends ChangeNotifier {
  final List<Track> tracks = [];
  final List<Track> deviceTracks = [];
  final List<MusicPlaylist> playlists = [];
  bool ready = false;
  bool busy = false;
  bool loading = false;
  bool scanning = false;
  bool deviceLoaded = false;
  bool get active => busy || loading;
  int quality = 192;
  String message = 'Tu música, a tu ritmo.';
  String deviceMessage =
      'Explora la música de tu teléfono sin mezclarla con las descargas.';
  late Directory folder;
  final spotify = SpotifyClient(
    readSession: readSpotifySession,
    writeSession: writeSpotifySession,
  );
  final List<SpotifyMatchRow> spotifyRows = [];
  String spotifyName = '';
  bool spotifyPlaylist = false;
  String lastDetail = '';
  int spotifySkipped = 0;
  bool _spotifyImporting = false;
  StopSignal _stop = StopSignal();
  static const engine = MethodChannel('ritmo/ytdlp');
  Future<void> _writes = Future.value();
  Track? current;
  Timer? _ticker;
  DateTime _phaseStart = DateTime.now();

  List<Track> get saved => tracks.where((t) => t.playable).toList();
  Track? lookup(String id) {
    for (final t in [...tracks, ...deviceTracks]) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  List<Track> playableList(MusicPlaylist p) => p.trackIds
      .map(lookup)
      .whereType<Track>()
      .where((t) => t.playable)
      .toList();

  Future<List<dynamic>> _read(String name) async {
    for (final candidate in [
      name,
      '$name.bak',
      if (name == 'library.json') 'library.bak',
    ]) {
      final file = File('${folder.path}/$candidate');
      if (!await file.exists()) {
        continue;
      }
      try {
        return jsonDecode(await file.readAsString()) as List<dynamic>;
      } catch (_) {}
    }
    return [];
  }

  Future<void> initialize() async {
    engine.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final event = Map<String, dynamic>.from(call.arguments as Map);
      final text = event['message'] as String? ?? '';
      final friendly = friendlyProgress(
        text,
        converting: event['converting'] == true,
        percent: (event['percent'] as num?)?.toDouble() ?? -1,
      );
      final t = current;
      if (t != null) {
        final converting = event['converting'] == true;
        final percent = (event['percent'] as num?)?.toDouble() ?? -1;
        final state = converting
            ? 'converting'
            : percent >= 0
            ? 'downloading'
            : t.state;
        if (t.state != state) _phase(t, state, friendly);
        t.phase = friendly;
        if (percent >= 0) {
          t.progress = (percent / 100).clamp(0.0, 1.0).toDouble();
          t.received = (event['received'] as num?)?.toInt() ?? 0;
          t.total = (event['total'] as num?)?.toInt() ?? 0;
        }
        if (text != 'Descargando audio') _record(t, text);
      }
      if (!_spotifyImporting) message = friendly;
      notifyListeners();
    });
    try {
      final root = await getApplicationDocumentsDirectory();
      folder = Directory('${root.path}/audio');
      await folder.create(recursive: true);
      await spotify.load(
        File('${folder.path}/spotify-config.json'),
        embeddedClientId: spotifyBuildClientId,
      );
      for (final raw in await _read('library.json')) {
        final t = Track.fromJson(Map<String, dynamic>.from(raw));
        if (t.state != 'done' || !await File(t.path).exists()) {
          t.state = 'pending';
        }
        tracks.add(t);
      }
      for (final raw in await _read('playlists.json')) {
        playlists.add(MusicPlaylist.fromJson(Map<String, dynamic>.from(raw)));
      }
      for (final raw in await _read('device.json')) {
        deviceTracks.add(Track.fromJson(Map<String, dynamic>.from(raw)));
      }
      await for (final f in folder.list()) {
        if (f is File &&
            (f.path.endsWith('.part') || f.path.endsWith('.source'))) {
          await f.delete();
        }
      }
      ready = true;
    } catch (e) {
      message = 'No se pudo abrir la biblioteca: $e';
    }
    notifyListeners();
  }

  Future<void> save() {
    final data = {
      'library.json': jsonEncode(tracks.map((t) => t.toJson()).toList()),
      'playlists.json': jsonEncode(playlists.map((p) => p.toJson()).toList()),
      'device.json': jsonEncode(deviceTracks.map((t) => t.toJson()).toList()),
    };
    final op = _writes.catchError((Object _) {}).then((_) async {
      for (final entry in data.entries) {
        final file = File('${folder.path}/${entry.key}');
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(entry.value, flush: true);
        if (await file.exists()) {
          await file.copy('${file.path}.bak');
        }
        await tmp.rename(file.path);
      }
    });
    _writes = op;
    return op;
  }

  Future<MusicPlaylist> createPlaylist(String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 80) {
      throw const FormatException('Usa un nombre de 1 a 80 caracteres.');
    }
    final p = MusicPlaylist(
      DateTime.now().microsecondsSinceEpoch.toString(),
      value,
    );
    playlists.add(p);
    await save();
    notifyListeners();
    return p;
  }

  Future<void> renamePlaylist(MusicPlaylist p, String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 80) {
      throw const FormatException('Usa un nombre de 1 a 80 caracteres.');
    }
    p.name = value;
    await save();
    notifyListeners();
  }

  Future<void> deletePlaylist(MusicPlaylist p) async {
    playlists.remove(p);
    await save();
    notifyListeners();
  }

  Future<void> addToPlaylist(MusicPlaylist p, Iterable<Track> values) async {
    for (final t in values) {
      p.add(t.id);
    }
    await save();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(MusicPlaylist p, String id) async {
    p.remove(id);
    await save();
    notifyListeners();
  }

  Future<void> moveInPlaylist(MusicPlaylist p, int from, int to) async {
    p.move(from, to);
    await save();
    notifyListeners();
  }

  Future<void> scanDevice({bool pickFiles = false}) async {
    if (!ready || scanning) {
      return;
    }
    scanning = true;
    deviceMessage = 'Buscando audio…';
    notifyListeners();
    try {
      final raw = await native.invokeMethod<List<dynamic>>(
        pickFiles ? 'pickAudio' : 'scanAudio',
      );
      final found = (raw ?? [])
          .map((r) => Track.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      if (pickFiles) {
        for (final t in found) {
          deviceTracks.removeWhere((old) => old.id == t.id);
          deviceTracks.add(t);
        }
      } else {
        final manual = deviceTracks
            .where((t) => t.id.startsWith('document:'))
            .toList();
        deviceTracks
          ..clear()
          ..addAll(found)
          ..addAll(manual);
      }
      deviceTracks.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      deviceLoaded = true;
      deviceMessage =
          '${deviceTracks.length} archivos de audio. Solo se leen; no se mueven ni se duplican.';
      await save();
    } on PlatformException catch (e) {
      deviceMessage =
          e.message ??
          'No se pudo acceder al audio. Revisa el permiso Música y audio.';
    } catch (e) {
      deviceMessage = 'No se pudo leer el teléfono: $e';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> add(String input, bool playlist) async {
    if (!ready || active) return;
    final link = parseYoutube(input, playlist);
    loading = true;
    _stop = StopSignal();
    message = 'Leyendo enlace con yt-dlp…';
    notifyListeners();
    try {
      final values =
          await engine.invokeListMethod<dynamic>('inspect', {
            'id': link.id,
            'playlist': link.playlist,
          }) ??
          [];
      _stop.check();
      var count = 0;
      for (final raw in values) {
        final item = Map<String, dynamic>.from(raw as Map);
        final id = item['id'] as String;
        if (!tracks.any((t) => t.id == id)) {
          tracks.add(
            Track(id, item['title'] as String, item['author'] as String),
          );
          count++;
        }
      }
      await save();
      message = '$count canciones añadidas. Pulsa Descargar cola.';
    } catch (e) {
      lastDetail = _safe(e);
      message = _stop.cancelled ? 'Lectura detenida.' : friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> updateEngine() async {
    if (active) return;
    loading = true;
    message = 'Actualizando yt-dlp desde el teléfono…';
    notifyListeners();
    try {
      final version = await engine.invokeMethod<String>('update');
      message = '${version ?? "yt-dlp actualizado"}. Ya puedes descargar.';
    } catch (e) {
      lastDetail = _safe(e);
      message = 'No se pudo actualizar el motor. Inténtalo después.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _phase(Track t, String state, String description) {
    t.state = state;
    t.phase = description;
    t.seconds = 0;
    _phaseStart = DateTime.now();
    message = description;
    notifyListeners();
  }

  String _safe(Object e) =>
      e.toString().replaceAll(RegExp(r'https?://\S+'), '[enlace]');
  void _record(Track t, String text) {
    t.diagnostics.add(text);
    if (t.diagnostics.length > 12) {
      t.diagnostics.removeAt(0);
    }
    debugPrint('[Ritmo] ${t.id}: $text');
  }

  Future<void> start() async {
    if (!ready || active) return;
    busy = true;
    _stop = StopSignal();
    notifyListeners();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final t = current;
      if (t != null) {
        t.seconds = DateTime.now().difference(_phaseStart).inSeconds;
        notifyListeners();
      }
    });
    try {
      await native.invokeMethod<void>('keepAwake', true);
      for (final t in tracks.where((t) => !t.playable).toList()) {
        if (_stop.cancelled) break;
        current = t;
        t.error = '';
        t.diagnostics.clear();
        t.progress = 0;
        t.received = 0;
        t.total = 0;
        try {
          _phase(t, 'resolving', 'Preparando yt-dlp + FFmpeg…');
          await save();
          _stop.check();
          final path = await engine.invokeMethod<String>('download', {
            'id': t.id,
            'folder': folder.path,
            'quality': quality,
          });
          if (path == null ||
              !await File(path).exists() ||
              await File(path).length() == 0) {
            throw StateError('No se encontró el MP3 terminado.');
          }
          t.path = path;
          t.state = 'done';
          t.progress = 1;
          t.phase = 'MP3 guardado';
        } catch (e) {
          t.state = _stop.cancelled ? 'pending' : 'error';
          t.phase = _stop.cancelled ? 'Detenida' : 'No se pudo completar';
          t.error = _stop.cancelled
              ? ''
              : '${_safe(e)}\n\nMotor: yt-dlp + FFmpeg\nID: ${t.id}\n${t.diagnostics.join('\n')}';
        } finally {
          await save();
          notifyListeners();
        }
      }
      final failed = tracks.where((t) => t.state == 'error').length;
      message = _stop.cancelled
          ? 'Detenida. Se conservaron los MP3 completos.'
          : failed > 0
          ? 'Finalizó con $failed errores. Abre Ver detalle.'
          : 'Tu música está lista para escuchar sin conexión.';
    } catch (e) {
      lastDetail = _safe(e);
      message = friendlyError(e);
    } finally {
      _ticker?.cancel();
      current = null;
      busy = false;
      try {
        await native.invokeMethod<void>('keepAwake', false);
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _stop.stop();
    spotify.cancel();
    message = 'Deteniendo yt-dlp…';
    notifyListeners();
    await engine.invokeMethod<void>('cancel');
  }

  Future<void> configureSpotify(String clientId) async {
    await spotify.configure(
      clientId,
      File('${folder.path}/spotify-config.json'),
    );
    notifyListeners();
  }

  Future<void> connectSpotify(Future<bool> Function(Uri) browser) async {
    if (active) return;
    loading = true;
    lastDetail = '';
    message = 'Autoriza Spotify en el navegador y vuelve a Ritmo.';
    notifyListeners();
    try {
      await spotify.connect(browser);
      message = spotify.sessionNotice.isEmpty
          ? 'Spotify conectado.'
          : spotify.sessionNotice;
    } catch (e) {
      lastDetail = _safe(e);
      message = e is SpotifyProblem ? e.message : friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> importSpotify(String link) async {
    if (!ready || active) return;
    parseSpotify(link);
    loading = true;
    _stop = StopSignal();
    _spotifyImporting = true;
    spotifyRows.clear();
    spotifyName = '';
    spotifySkipped = 0;
    lastDetail = '';
    message = 'Leyendo Spotify…';
    notifyListeners();
    try {
      final collection = await spotify.read(link, (count) {
        message = 'Leyendo playlist · $count canciones';
        notifyListeners();
      });
      spotifyName = collection.name;
      spotifyPlaylist = collection.playlist;
      spotifySkipped = collection.skipped;
      for (var i = 0; i < collection.songs.length; i++) {
        _stop.check();
        final song = collection.songs[i];
        message =
            'Buscando coincidencias · ${i + 1} de ${collection.songs.length}';
        notifyListeners();
        try {
          final result =
              await engine.invokeListMethod<dynamic>('search', {
                'query': song.query.length > 500
                    ? song.query.substring(0, 500)
                    : song.query,
              }) ??
              [];
          _stop.check();
          final videos = result
              .map(
                (r) => VideoMatch.fromJson(Map<String, dynamic>.from(r as Map)),
              )
              .toList();
          spotifyRows.add(SpotifyMatchRow(song, rankMatches(song, videos)));
        } catch (e) {
          if (_stop.cancelled) rethrow;
          lastDetail = _safe(e);
          spotifyRows.add(SpotifyMatchRow(song, [], error: friendlyError(e)));
        }
        notifyListeners();
      }
      message = 'Revisa las coincidencias antes de añadirlas.';
    } catch (e) {
      lastDetail = _safe(e);
      message = _stop.cancelled
          ? 'Búsqueda detenida. Puedes revisar lo encontrado.'
          : e is SpotifyProblem
          ? e.message
          : friendlyError(e);
    } finally {
      _spotifyImporting = false;
      loading = false;
      notifyListeners();
    }
  }

  void selectSpotifyMatch(SpotifyMatchRow row, VideoMatch? video) {
    row.selected = video;
    notifyListeners();
  }

  Future<void> enqueueSpotify() async {
    if (active) return;
    final chosen = spotifyRows.where((r) => r.selected != null).toList();
    if (chosen.isEmpty) return;
    final addedIds = <String>[];
    for (final row in chosen) {
      final v = row.selected!;
      if (!tracks.any((t) => t.id == v.id)) {
        tracks.add(Track(v.id, row.song.title, row.song.artist));
      }
      addedIds.add(v.id);
    }
    if (spotifyPlaylist) {
      final list = MusicPlaylist(
        DateTime.now().microsecondsSinceEpoch.toString(),
        spotifyName,
      );
      for (final id in addedIds) {
        list.add(id);
      }
      playlists.add(list);
    }
    await save();
    spotifyRows.clear();
    message = '${chosen.length} canciones añadidas. Pulsa Descargar cola.';
    notifyListeners();
  }

  Future<void> remove(Track t) async {
    if (active || t.device) {
      return;
    }
    if (t.path.isNotEmpty && await File(t.path).exists()) {
      await File(t.path).delete();
    }
    tracks.remove(t);
    for (final p in playlists) {
      p.remove(t.id);
    }
    await save();
    notifyListeners();
  }
}
