class Track {
  final String id;
  final String title;
  final String author;
  final bool device;
  final String folder;
  String state;
  String path;
  String error;
  String phase = '';
  double progress = 0;
  int received = 0;
  int total = 0;
  int seconds = 0;
  final List<String> diagnostics = [];
  Track(
    this.id,
    this.title,
    this.author, {
    this.state = 'pending',
    this.path = '',
    this.error = '',
    this.device = false,
    this.folder = '',
  });
  bool get playable => state == 'done' && path.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'state': state,
    'path': path,
    'error': error,
    'device': device,
    'folder': folder,
  };
  factory Track.fromJson(Map<String, dynamic> j) => Track(
    j['id'] as String,
    j['title'] as String,
    j['author'] as String,
    state: j['state'] as String? ?? 'pending',
    path: j['path'] as String? ?? '',
    error: j['error'] as String? ?? '',
    device: j['device'] == true,
    folder: j['folder'] as String? ?? '',
  );
}

class MusicPlaylist {
  final String id;
  String name;
  final List<String> trackIds;
  MusicPlaylist(this.id, this.name, [List<String>? tracks])
    : trackIds = List.of(tracks ?? []);
  bool add(String trackId) {
    if (trackIds.contains(trackId)) {
      return false;
    }
    trackIds.add(trackId);
    return true;
  }

  void remove(String trackId) => trackIds.remove(trackId);
  void move(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex--;
    }
    final id = trackIds.removeAt(oldIndex);
    trackIds.insert(newIndex, id);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'tracks': trackIds};
  factory MusicPlaylist.fromJson(Map<String, dynamic> j) => MusicPlaylist(
    j['id'] as String,
    j['name'] as String,
    (j['tracks'] as List<dynamic>).cast<String>(),
  );
}
