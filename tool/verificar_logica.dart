import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/models.dart';
import '../lib/links.dart';
import '../lib/transfer.dart';

Future<void> main() async {
  var checks = 0;
  void verify(bool condition, String detail) {
    if (!condition) {
      throw StateError(detail);
    }
    checks++;
  }

  final p = MusicPlaylist('1', 'Prueba');
  verify(p.add('a'), 'add');
  verify(!p.add('a'), 'no duplicates');
  p.add('b');
  p.add('c');
  p.move(0, 3);
  verify(p.trackIds.join() == 'bca', 'move down');
  p.move(2, 0);
  verify(p.trackIds.join() == 'abc', 'move up');
  p.remove('b');
  verify(p.trackIds.join() == 'ac', 'remove preserves others');
  final restored = MusicPlaylist.fromJson(
    jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
  );
  verify(
    restored.trackIds.join() == 'ac' && restored.name == 'Prueba',
    'playlist round trip',
  );
  final old = Track.fromJson({
    'id': 'abcdefghijk',
    'title': 'Título',
    'author': 'Autor',
    'state': 'done',
    'path': '/audio/x.mp3',
  });
  verify(old.playable && !old.device, 'legacy library compatible');
  final local = Track.fromJson({
    'id': 'device:7',
    'title': 'Local',
    'author': 'Artista',
    'path': 'content://media/external/audio/media/7',
    'state': 'done',
    'device': true,
    'folder': 'Music',
  });
  verify(local.device && local.folder == 'Music', 'local audio preserved');
  verify(
    parseYoutube('https://youtu.be/abcdefghijk?si=x', false).id ==
        'abcdefghijk',
    'short URL',
  );
  verify(
    parseYoutube(
          'https://music.youtube.com/watch?v=abcdefghijk&list=PLabcdefghijklmnop',
          true,
        ).id ==
        'PLabcdefghijklmnop',
    'playlist URL',
  );
  for (final url in [
    'file:///audio.mp3',
    'https://youtube.com.evil.test/watch?v=abcdefghijk',
    'https://open.spotify.com/track/abc',
  ]) {
    var rejected = false;
    try {
      parseYoutube(url, false);
    } on FormatException {
      rejected = true;
    }
    verify(rejected, 'invalid URL rejected');
  }
  final dir = await Directory.systemTemp.createTemp('ritmo_logic_');
  try {
    final f = File('${dir.path}/audio.source');
    final progress = <int>[];
    final count = await writeAudioStream(
      stream: Stream.fromIterable([
        [1, 2],
        [3, 4, 5],
      ]),
      destination: f,
      stop: StopSignal(),
      expectedBytes: 5,
      progress: (n, _) => progress.add(n),
    );
    verify(
      count == 5 && (await f.readAsBytes()).join(',') == '1,2,3,4,5',
      'stream content',
    );
    verify(progress.join(',') == '2,5', 'progress uses real bytes');
    for (final chunks in <List<List<int>>>[
      [],
      [
        [1, 2],
      ],
    ]) {
      var rejected = false;
      try {
        await writeAudioStream(
          stream: Stream.fromIterable(chunks),
          destination: f,
          stop: StopSignal(),
          expectedBytes: 5,
          progress: (_, expected) {},
        );
      } on FileSystemException {
        rejected = true;
      }
      verify(rejected && !await f.exists(), 'incomplete file removed');
    }
    final stalled = StreamController<List<int>>();
    var timedOut = false;
    try {
      await writeAudioStream(
        stream: stalled.stream,
        destination: f,
        stop: StopSignal(),
        expectedBytes: 5,
        progress: (_, expected) {},
        idleTimeout: const Duration(milliseconds: 30),
      );
    } on TimeoutException {
      timedOut = true;
    }
    await stalled.close();
    verify(timedOut && !await f.exists(), 'stall times out and cleans up');
    final stop = StopSignal();
    final waiting = StreamController<List<int>>();
    final timer = Timer(const Duration(milliseconds: 30), stop.stop);
    var cancelled = false;
    try {
      await writeAudioStream(
        stream: waiting.stream,
        destination: f,
        stop: stop,
        expectedBytes: 5,
        progress: (_, expected) {},
      );
    } on TransferCancelled {
      cancelled = true;
    }
    timer.cancel();
    await waiting.close();
    verify(
      cancelled && !await f.exists(),
      'cancel does not wait for a network event',
    );
    final unknown = await writeAudioStream(
      stream: Stream.fromIterable([
        [1, 2, 3],
      ]),
      destination: f,
      stop: StopSignal(),
      expectedBytes: 0,
      progress: (_, expected) {},
    );
    verify(unknown == 3, 'unknown content length');
    final pre = StopSignal()..stop();
    var preCancelled = false;
    try {
      await writeAudioStream(
        stream: const Stream<List<int>>.empty(),
        destination: File('${dir.path}/pre'),
        stop: pre,
        expectedBytes: 1,
        progress: (_, expected) {},
      );
    } on TransferCancelled {
      preCancelled = true;
    }
    verify(preCancelled, 'cancel before opening');
  } finally {
    await dir.delete(recursive: true);
  }
  stdout.writeln(
    '$checks comprobaciones correctas: playlists, compatibilidad, enlaces y transferencias.',
  );
}
