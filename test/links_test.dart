import 'package:flutter_test/flutter_test.dart';
import 'package:nube_music/links.dart';

void main() {
  test('Video compartido con parámetros', () {
    expect(
      parseYoutube('https://youtu.be/abcdefghijk?si=abc', false).id,
      'abcdefghijk',
    );
  });
  test('YouTube Music', () {
    expect(
      parseYoutube('https://music.youtube.com/watch?v=abcdefghijk', false).id,
      'abcdefghijk',
    );
  });
  test('Playlist desde enlace a canción', () {
    final parsed = parseYoutube(
      'https://www.youtube.com/watch?v=abcdefghijk&list=PLabcdefghijklmnop',
      true,
    );
    expect(parsed.id, 'PLabcdefghijklmnop');
    expect(parsed.playlist, true);
  });
  test('Modo canción ignora la playlist', () {
    expect(
      parseYoutube(
        'https://www.youtube.com/watch?v=abcdefghijk&list=PLabcdefghijklmnop',
        false,
      ).id,
      'abcdefghijk',
    );
  });
  test('Shorts', () {
    expect(
      parseYoutube('https://www.youtube.com/shorts/abcdefghijk', false).id,
      'abcdefghijk',
    );
  });
  test('Rechaza dominios impostores, Spotify, texto y video incompleto', () {
    for (final value in [
      'https://youtube.com.evil.test/watch?v=abcdefghijk',
      'https://open.spotify.com/track/abc',
      'hola',
      'https://youtube.com/watch?v=abc',
      'file:///tmp/abcdefghijk',
    ]) {
      expect(() => parseYoutube(value, false), throwsFormatException);
    }
  });
  test('Playlist requiere identificador', () {
    expect(
      () => parseYoutube('https://youtube.com/watch?v=abcdefghijk', true),
      throwsFormatException,
    );
  });
}
