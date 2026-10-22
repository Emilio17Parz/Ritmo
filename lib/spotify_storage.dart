import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _key = 'ritmo.spotify.session.v1';
Future<String?> readSpotifySession() => _storage.read(key: _key);
Future<void> writeSpotifySession(String? value) => value == null
    ? _storage.delete(key: _key)
    : _storage.write(key: _key, value: value);
