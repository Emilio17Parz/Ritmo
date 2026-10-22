class SourceLink {
  final String id;
  final bool playlist;
  const SourceLink(this.id, this.playlist);
}

SourceLink parseYoutube(String input, bool playlist) {
  final uri = Uri.tryParse(input.trim());
  const hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
  };
  if (uri == null ||
      uri.scheme != 'https' ||
      !hosts.contains(uri.host) ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException(
      'Pega un enlace HTTPS de YouTube o YouTube Music.',
    );
  }
  if (playlist) {
    final id = uri.queryParameters['list'] ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{10,100}$').hasMatch(id)) {
      throw const FormatException(
        'El enlace no contiene una playlist (list=...).',
      );
    }
    return SourceLink(id, true);
  }
  var id = uri.queryParameters['v'] ?? '';
  if (uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    id = uri.pathSegments.first;
  }
  if (uri.pathSegments.length >= 2 &&
      ['shorts', 'live'].contains(uri.pathSegments.first)) {
    id = uri.pathSegments[1];
  }
  if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
    throw const FormatException(
      'Pega una canción o cambia el selector a Playlist.',
    );
  }
  return SourceLink(id, false);
}
