import 'package:flutter_test/flutter_test.dart';

import '../tool/verificar_spotify.dart' as checks;
import '../tool/verificar_sesion.dart' as session;

void main() {
  // Ambos comprueban el mismo puerto local; se ejecutan secuencialmente.
  test('Spotify: importación, PKCE y sesión persistente', () async {
    await checks.main();
    await session.main();
  });
}
