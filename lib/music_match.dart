class SpotifySong {
  final String id, title;
  final List<String> artists;
  final int durationMs;
  SpotifySong(this.id, this.title, this.artists, this.durationMs);
  String get artist => artists.join(', ');
  String get query => '$title ${artists.join(' ')} audio';
}

class VideoMatch {
  final String id, title, author;
  final double duration;
  double score = 0;
  bool confident = false;
  VideoMatch(this.id, this.title, this.author, this.duration);
  factory VideoMatch.fromJson(Map<String, dynamic> j) => VideoMatch(
    j['id'] as String,
    j['title'] as String? ?? '',
    j['author'] as String? ?? '',
    (j['duration'] as num?)?.toDouble() ?? 0,
  );
}

class SpotifyMatchRow {
  final SpotifySong song;
  final List<VideoMatch> candidates;
  VideoMatch? selected;
  String? error;
  SpotifyMatchRow(this.song, this.candidates, {this.error}) {
    if (candidates.isNotEmpty && candidates.first.confident)
      selected = candidates.first;
  }
}

String normalizeMusic(String value) {
  var result = value.toLowerCase();
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaaeeeeiiiiooooouuuunc';
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }
  return result
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> _words(String s) =>
    normalizeMusic(s).split(' ').where((w) => w.length > 1).toSet();
double _coverage(Set<String> wanted, Set<String> found) =>
    wanted.isEmpty ? 0 : wanted.intersection(found).length / wanted.length;

List<VideoMatch> rankMatches(SpotifySong song, List<VideoMatch> videos) {
  final titleWords = _words(song.title);
  final artistWords = _words(song.artists.isEmpty ? '' : song.artists.first);
  const variants = [
    'live',
    'cover',
    'karaoke',
    'remix',
    'instrumental',
    'sped',
    'slowed',
  ];
  for (final v in videos) {
    final words = _words('${v.title} ${v.author}');
    final title = _coverage(titleWords, _words(v.title));
    final artist = _coverage(artistWords, words);
    final known = v.duration > 0 && song.durationMs > 0;
    final delta = (v.duration - song.durationMs / 1000).abs();
    final close =
        known && delta <= (song.durationMs / 1000 * 0.03).clamp(5, 12);
    final unwanted = variants.any(
      (w) => words.contains(w) && !titleWords.contains(w),
    );
    v.score =
        title * .55 + artist * .30 + (close ? .15 : 0) - (unwanted ? .4 : 0);
    v.confident =
        !unwanted && close && title >= .85 && artist >= .66 && v.score >= .85;
  }
  videos.sort((a, b) => b.score.compareTo(a.score));
  return videos;
}

class SpotifySource {
  final String kind, id;
  SpotifySource(this.kind, this.id);
}

SpotifySource parseSpotify(String input) {
  final raw = input.trim();
  final uri = Uri.tryParse(raw);
  List<String> parts;
  if (raw.startsWith('spotify:')) {
    parts = raw.split(':').skip(1).toList();
  } else if (uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'open.spotify.com' &&
      uri.userInfo.isEmpty) {
    parts = uri.pathSegments.where((p) => !p.startsWith('intl-')).toList();
  } else {
    throw const FormatException(
      'Pega el enlace completo de una canción o playlist de Spotify.',
    );
  }
  if (parts.length != 2 ||
      !['track', 'playlist'].contains(parts[0]) ||
      !RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(parts[1])) {
    throw const FormatException(
      'Usa un enlace de canción o playlist de Spotify, no de álbum o artista.',
    );
  }
  return SpotifySource(parts[0], parts[1]);
}
