import 'dart:async';
import 'dart:io';

import 'transfer.dart';

/// One bounded request. Never silently refresh a rejected media URL.
Stream<List<int>> openAudioStream(
  Uri url, {
  required StopSignal stop,
  required int expectedBytes,
  required void Function(String) report,
  Duration timeout = const Duration(seconds: 20),
}) async* {
  if (!url.hasAuthority ||
      url.host.isEmpty ||
      (url.scheme != 'https' && url.scheme != 'http')) {
    throw const FormatException(
      'El proveedor devolvió una URL de audio inválida.',
    );
  }
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    stop.check();
    report('Abriendo conexión de audio');
    final request = await stop.guard(client.getUrl(url), timeout);
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (expectedBytes > 0) {
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=0-${expectedBytes - 1}',
      );
    }
    final response = await stop.guard(request.close(), timeout);
    report('Servidor de audio: HTTP ${response.statusCode}');
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException(
        'El servidor rechazó el audio: HTTP ${response.statusCode}.',
      );
    }
    if (response.statusCode == 206) {
      final range =
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      if (!RegExp(r'^bytes 0-\d+/\d+$').hasMatch(range)) {
        throw const HttpException(
          'El servidor devolvió un rango de audio inesperado.',
        );
      }
    }
    final type = response.headers.contentType?.mimeType ?? '';
    if (type.contains('text/') || type.contains('json')) {
      throw const HttpException(
        'El servidor devolvió texto en lugar de audio.',
      );
    }
    yield* response.timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
