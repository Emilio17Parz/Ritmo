import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nube_music/downloads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engine = MethodChannel('ritmo/ytdlp');
  const files = MethodChannel('nube_music/files');
  late Directory root;
  late Downloads library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ritmo_bridge_');
    library = Downloads()
      ..folder = root
      ..ready = true;
    messenger.setMockMethodCallHandler(files, (_) async => null);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(engine, null);
    messenger.setMockMethodCallHandler(files, null);
    library.dispose();
    await root.delete(recursive: true);
  });
  test('Playlist nativa conserva orden y elimina duplicados', () async {
    messenger.setMockMethodCallHandler(engine, (call) async {
      expect(call.method, 'inspect');
      expect(call.arguments['playlist'], true);
      return [
        {'id': '9OARUBgt_JQ', 'title': 'Uno', 'author': 'Autor'},
        {'id': 'snKRwH4qUA4', 'title': 'Dos', 'author': 'Autor'},
      ];
    });
    const link = 'https://www.youtube.com/playlist?list=PL1234567890123';
    await library.add(link, true);
    await library.add(link, true);
    expect(library.tracks.map((t) => t.title), ['Uno', 'Dos']);
  });
  test('MP3 nativo se guarda y no se descarga dos veces', () async {
    var calls = 0;
    library.tracks.add(Track('9OARUBgt_JQ', 'Uno', 'Autor'));
    messenger.setMockMethodCallHandler(engine, (call) async {
      expect(call.method, 'download');
      calls++;
      final file = File('${root.path}/9OARUBgt_JQ.mp3');
      await file.writeAsBytes([73, 68, 51, 1]);
      return file.path;
    });
    await library.start();
    await library.start();
    expect(calls, 1);
    expect(library.saved.length, 1);
  });
  test('Error nativo no marca descarga como completada', () async {
    library.tracks.add(Track('9OARUBgt_JQ', 'Uno', 'Autor'));
    messenger.setMockMethodCallHandler(engine, (_) async {
      throw PlatformException(code: 'YTDLP', message: 'HTTP Error 403');
    });
    await library.start();
    expect(library.tracks.single.state, 'error');
    expect(library.tracks.single.error, contains('403'));
    expect(library.saved, isEmpty);
  });
  test('Cancelar conserva la canción pendiente', () async {
    library.tracks.add(Track('9OARUBgt_JQ', 'Uno', 'Autor'));
    final entered = Completer<void>();
    final finish = Completer<String>();
    messenger.setMockMethodCallHandler(engine, (call) async {
      if (call.method == 'cancel') {
        finish.completeError(PlatformException(code: 'CANCELLED'));
        return null;
      }
      entered.complete();
      return await finish.future;
    });
    final running = library.start();
    await entered.future;
    await library.stop();
    await running;
    expect(library.tracks.single.state, 'pending');
    expect(library.busy, false);
  });
}
