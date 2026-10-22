import 'package:flutter_test/flutter_test.dart';

import '../tool/verificar_logica.dart' as logic;

void main() {
  test('Playlists y transferencias: progreso, cancelacion y timeout', () async {
    await logic.main();
  });
}
