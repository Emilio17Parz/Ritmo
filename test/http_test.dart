import 'package:flutter_test/flutter_test.dart';

import '../tool/verificar_http.dart' as checks;

void main() {
  test('HTTP: audio, rechazo, URL y cancelación', checks.main);
}
