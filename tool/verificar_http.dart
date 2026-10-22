import 'dart:io';

import '../lib/http_audio.dart';
import '../lib/transfer.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType('audio', 'mp4');
    switch (request.uri.path) {
      case '/ok':
        request.response.headers.contentType = ContentType('audio', 'mp4');
        request.response.add([1, 2, 3]);
      case '/denied':
        request.response.statusCode = 403;
      case '/text':
        request.response.headers.contentType = ContentType.html;
        request.response.write('Not audio');
      case '/partial':
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 0-2/3');
        request.response.add([1, 2, 3]);
      case '/wrong':
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 1-2/3');
        request.response.add([2, 3]);
    }
    await request.response.close();
  });
  var checks = 0;
  Future<List<int>> read(Uri uri, {StopSignal? stop}) async {
    final bytes = <int>[];
    await for (final chunk in openAudioStream(
      uri,
      stop: stop ?? StopSignal(),
      expectedBytes: 3,
      report: (_) {},
    )) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  try {
    for (final path in ['/ok', '/partial']) {
      final bytes = await read(
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      if (bytes.join(',') != '1,2,3') throw StateError('Audio mismatch');
      checks++;
    }
    for (final path in ['/denied', '/text', '/wrong']) {
      var failed = false;
      try {
        await read(Uri.parse('http://127.0.0.1:${server.port}$path'));
      } on HttpException {
        failed = true;
      }
      if (!failed) throw StateError('Must reject $path');
      checks++;
    }
    try {
      await read(Uri());
      throw StateError('Accepted empty URL');
    } on FormatException {
      checks++;
    }
    try {
      await read(
        Uri.parse('http://127.0.0.1:${server.port}/ok'),
        stop: StopSignal()..stop(),
      );
      throw StateError('Ignored cancellation');
    } on TransferCancelled {
      checks++;
    }
    print('$checks pruebas HTTP correctas.');
  } finally {
    await server.close(force: true);
  }
}
