import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import 'downloads.dart';
import 'spotify_page.dart';
import 'music_match.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RitmoApp());
}

const accent = Color(0xFFCBACFF);
const warm = Color(0xFFF6B785);

class RitmoApp extends StatelessWidget {
  const RitmoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ritmo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF110E17),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF211B2C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const Home(),
  );
}

Future<String?> askName(
  BuildContext context,
  String title, [
  String initial = '',
]) async {
  final field = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(hintText: 'Nombre de la playlist'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (field.text.trim().isNotEmpty) {
              Navigator.pop(c, field.text.trim());
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  // Dialog animations can still reference the controller after Navigator.pop.
  Future<void>.delayed(const Duration(seconds: 1), field.dispose);
  return result;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final library = Downloads();
  final input = TextEditingController();
  final search = TextEditingController();
  final player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSubscription;
  List<Track> _playQueue = [];
  int _playIndex = 0;
  int tab = 0;
  bool playlistLink = false;
  bool moving = false;
  bool playingNow = false;
  Track? playing;
  String? folderFilter;
  @override
  void initState() {
    super.initState();
    unawaited(library.initialize());
    _playerSubscription = player.playerStateStream.listen((s) {
      if (mounted) {
        setState(
          () => playingNow =
              s.playing && s.processingState != ProcessingState.completed,
        );
      }
      if (s.processingState == ProcessingState.completed &&
          !moving &&
          _playIndex + 1 < _playQueue.length) {
        unawaited(playQueue(_playQueue, _playIndex + 1));
      }
    });
  }

  @override
  void dispose() {
    unawaited(_playerSubscription?.cancel());
    unawaited(library.stop());
    unawaited(player.dispose());
    input.dispose();
    search.dispose();
    super.dispose();
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> action(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      toast(e.toString());
    }
  }

  Future<void> playQueue(List<Track> items, int index) async {
    if (moving || items.isEmpty || index < 0 || index >= items.length) {
      return;
    }
    moving = true;
    try {
      final t = items[index];
      await player.stop();
      if (t.device) {
        await player.setAudioSource(AudioSource.uri(Uri.parse(t.path)));
      } else {
        await player.setFilePath(t.path);
      }
      _playQueue = List.of(items);
      _playIndex = index;
      if (mounted) {
        setState(() => playing = t);
      }
      unawaited(
        player.play().catchError((Object e) {
          toast('No se pudo reproducir: $e');
        }),
      );
    } catch (e) {
      toast(
        'No se pudo abrir el audio. Si es del teléfono, revisa el permiso o elige el archivo de nuevo.\n$e',
      );
    } finally {
      moving = false;
    }
  }

  Future<void> addLink() async {
    final text = input.text.trim();
    final uri = Uri.tryParse(text);
    if (uri?.scheme == 'spotify' ||
        uri?.host == 'open.spotify.com' ||
        uri?.host == 'spotify.link') {
      await action(() async {
        parseSpotify(text);
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SpotifyPage(library: library, sourceLink: text),
          ),
        );
      });
      return;
    }
    await action(() => library.add(text, playlistLink));
  }

  Future<void> newPlaylist() async {
    final name = await askName(context, 'Nueva playlist');
    if (name != null) {
      await action(() async {
        await library.createPlaylist(name);
      });
    }
  }

  Future<void> addToPlaylist(Track t) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Añadir a playlist')),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Crear playlist'),
              onTap: () => Navigator.pop(c, 'new'),
            ),
            ...library.playlists.map(
              (p) => ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(p.name),
                subtitle: Text('${p.trackIds.length} canciones'),
                onTap: () => Navigator.pop(c, p.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    await action(() async {
      MusicPlaylist? p;
      if (selected == 'new') {
        final name = await askName(context, 'Nueva playlist');
        if (name == null) {
          return;
        }
        p = await library.createPlaylist(name);
      } else {
        for (final candidate in library.playlists) {
          if (candidate.id == selected) {
            p = candidate;
            break;
          }
        }
      }
      if (p != null) {
        await library.addToPlaylist(p, [t]);
        toast('Añadida a ${p.name}.');
      }
    });
  }

  Future<void> deleteTrack(Track t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Eliminar descarga?'),
        content: Text(t.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Conservar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true) {
      return;
    }
    await action(() async {
      if (playing?.id == t.id) {
        await player.stop();
        if (mounted) {
          setState(() => playing = null);
        }
      }
      _playQueue.removeWhere((v) => v.id == t.id);
      await library.remove(t);
    });
  }

  Future<void> trackMenu(String value, Track t) async {
    if (value == 'playlist') {
      await addToPlaylist(t);
    }
    if (value == 'delete') {
      await deleteTrack(t);
    }
    if (value == 'export') {
      await action(() async {
        if (await native.invokeMethod<bool>('export', {
              'path': t.path,
              'name': '${t.title}.mp3',
            }) ==
            true) {
          toast('MP3 guardado.');
        }
      });
    }
    if (value == 'share') {
      await action(() async {
        await Share.shareXFiles(
          [XFile(t.path, mimeType: 'audio/mpeg')],
          fileNameOverrides: [
            '${t.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.mp3',
          ],
        );
      });
    }
  }

  Widget song(Track t, List<Track> group, int index) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    leading: CircleAvatar(
      backgroundColor: const Color(0xFF342344),
      child: Icon(
        playing?.id == t.id ? Icons.equalizer : Icons.play_arrow_rounded,
        color: accent,
      ),
    ),
    title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(t.author, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () => playQueue(group, index),
    trailing: PopupMenuButton<String>(
      onSelected: (v) => trackMenu(v, t),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'playlist',
          child: Text('Añadir a playlist'),
        ),
        if (!t.device) ...[
          const PopupMenuItem(
            value: 'export',
            child: Text('Guardar en carpeta…'),
          ),
          const PopupMenuItem(value: 'share', child: Text('Compartir MP3')),
          if (!library.active)
            const PopupMenuItem(
              value: 'delete',
              child: Text('Eliminar descarga'),
            ),
        ],
      ],
    ),
  );
  Widget searchBox(String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: TextField(
      controller: search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
      ),
    ),
  );
  bool matches(Track t) => '${t.title} ${t.author}'.toLowerCase().contains(
    search.text.toLowerCase(),
  );
  Widget empty(String text, IconData icon) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: accent),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
  Widget header(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Colors.white60)),
      ],
    ),
  );

  Widget downloadsPage() {
    final pending = library.tracks.where((t) => !t.playable).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF493258), Color(0xFF302338)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A TU RITMO',
                style: TextStyle(letterSpacing: 3, fontSize: 11, color: warm),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tu próxima\ncanción favorita.',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${library.saved.length} MP3 guardados · ${pending.length} en cola',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: library.active || !library.ready
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SpotifyPage(library: library),
                  ),
                ),
          icon: const Icon(Icons.library_music),
          label: Text(
            library.spotify.connected
                ? 'Spotify conectado · ajustes'
                : 'Configurar Spotify',
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Canción YT'),
              icon: Icon(Icons.music_note),
            ),
            ButtonSegment(
              value: true,
              label: Text('Playlist YT'),
              icon: Icon(Icons.queue_music),
            ),
          ],
          selected: {playlistLink},
          onSelectionChanged: library.active
              ? null
              : (s) => setState(() => playlistLink = s.first),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: input,
          enabled: !library.active,
          minLines: 1,
          maxLines: 3,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'Enlace de YouTube o Spotify',
            helperText:
                'Canción o playlist. Spotify se detecta automáticamente.',
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste),
              onPressed: library.active
                  ? null
                  : () async {
                      final data = await Clipboard.getData('text/plain');
                      if (mounted && data?.text != null) {
                        input.text = data!.text!;
                      }
                    },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: library.quality,
              items: [128, 192, 320]
                  .map(
                    (q) => DropdownMenuItem(
                      value: q,
                      child: Text('MP3 · $q kbps'),
                    ),
                  )
                  .toList(),
              onChanged: library.active
                  ? null
                  : (v) => setState(() => library.quality = v ?? 192),
            ),
            FilledButton.tonalIcon(
              onPressed: library.active || !library.ready ? null : addLink,
              icon: const Icon(Icons.add),
              label: const Text('Continuar'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: library.active || !library.ready || pending.isEmpty
              ? null
              : library.start,
          icon: const Icon(Icons.download),
          label: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Descargar cola'),
          ),
        ),
        if (library.active)
          OutlinedButton.icon(
            onPressed: library.stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Detener'),
          ),
        const SizedBox(height: 12),
        Text(library.message, maxLines: 3, overflow: TextOverflow.ellipsis),
        if (library.lastDetail.isNotEmpty)
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Detalle técnico'),
                content: SingleChildScrollView(
                  child: SelectableText(library.lastDetail),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: library.lastDetail),
                    ),
                    child: const Text('Copiar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
            child: const Text('Ver detalle'),
          ),
        if (library.active)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Mantén la app abierta mientras descarga y convierte.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'En cola',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Añade un enlace para comenzar.'),
          ),
        ...pending.map((t) {
          final processing = [
            'resolving',
            'connecting',
            'downloading',
            'converting',
          ].contains(t.state);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!library.active)
                        IconButton(
                          onPressed: () => deleteTrack(t),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.phase.isEmpty
                        ? (t.state == 'error' ? 'Error' : 'Pendiente')
                        : t.phase,
                    style: TextStyle(color: t.state == 'error' ? warm : accent),
                  ),
                  if (processing) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: t.state == 'downloading' && t.total > 0
                          ? t.progress
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.state == 'downloading'
                          ? '${(t.received / 1048576).toStringAsFixed(2)} MB${t.total > 0 ? ' / ${(t.total / 1048576).toStringAsFixed(2)} MB · ${(t.progress * 100).round()}%' : ''}'
                          : '${t.seconds} s en esta etapa',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                  if (t.error.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Detalle de descarga'),
                          content: SingleChildScrollView(
                            child: SelectableText(t.error),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: t.error));
                                toast('Detalle copiado.');
                              },
                              child: const Text('Copiar detalle'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Cerrar'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Ver detalle'),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget savedPage() {
    final songs = library.saved.where(matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header('Tus descargas', 'MP3 de Ritmo, disponibles sin conexión.'),
        searchBox('Buscar descargas'),
        Expanded(
          child: songs.isEmpty
              ? empty(
                  'Aquí aparecerán tus canciones descargadas.',
                  Icons.download_done,
                )
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (_, i) => song(songs[i], songs, i),
                ),
        ),
      ],
    );
  }

  Widget devicePage() {
    final folders = library.deviceTracks.map((t) => t.folder).toSet().toList()
      ..sort();
    final selected = folders.contains(folderFilter) ? folderFilter : null;
    final songs = library.deviceTracks
        .where((t) => matches(t) && (selected == null || t.folder == selected))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(
          'En tu teléfono',
          'Tu música existente, en una sección separada.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: library.scanning || !library.ready
                    ? null
                    : () => library.scanDevice(),
                icon: const Icon(Icons.folder_open),
                label: const Text('Explorar música'),
              ),
              TextButton.icon(
                onPressed: library.scanning || !library.ready
                    ? null
                    : () => library.scanDevice(pickFiles: true),
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('Elegir archivos'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            library.deviceMessage,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ),
        if (library.scanning) const LinearProgressIndicator(),
        searchBox('Buscar en el teléfono'),
        if (folders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected ?? '',
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Todas las carpetas'),
                ),
                ...folders.map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: Text(f, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (s) =>
                  setState(() => folderFilter = s == '' ? null : s),
            ),
          ),
        Expanded(
          child: songs.isEmpty
              ? empty(
                  'Pulsa Explorar música o elige archivos de audio.',
                  Icons.library_music_outlined,
                )
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (_, i) => song(songs[i], songs, i),
                ),
        ),
      ],
    );
  }

  Widget playlistsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header('Hechas por ti', 'Combina descargas y música del teléfono.'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FilledButton.tonalIcon(
          onPressed: library.ready ? newPlaylist : null,
          icon: const Icon(Icons.add),
          label: const Text('Nueva playlist'),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: library.playlists.isEmpty
            ? empty(
                'Crea una playlist y añade tus canciones.',
                Icons.queue_music,
              )
            : ListView.builder(
                itemCount: library.playlists.length,
                itemBuilder: (_, i) {
                  final p = library.playlists[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF493258),
                      child: Icon(Icons.queue_music, color: accent),
                    ),
                    title: Text(p.name),
                    subtitle: Text('${p.trackIds.length} canciones'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistPage(
                          library: library,
                          playlist: p,
                          play: playQueue,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
  String clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  Widget miniPlayer() => Container(
    color: const Color(0xFF302338),
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                playing!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: _playIndex > 0
                  ? () => playQueue(_playQueue, _playIndex - 1)
                  : null,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              icon: Icon(playingNow ? Icons.pause : Icons.play_arrow),
              onPressed: () => action(() async {
                if (playingNow) {
                  await player.pause();
                } else {
                  if (player.processingState == ProcessingState.completed) {
                    await player.seek(Duration.zero);
                  }
                  unawaited(
                    player.play().catchError((Object e) {
                      toast(e.toString());
                    }),
                  );
                }
              }),
            ),
            IconButton(
              onPressed: _playIndex + 1 < _playQueue.length
                  ? () => playQueue(_playQueue, _playIndex + 1)
                  : null,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              onPressed: () => action(() async {
                await player.stop();
                _playQueue = [];
                if (mounted) {
                  setState(() => playing = null);
                }
              }),
              icon: const Icon(Icons.close, size: 19),
            ),
          ],
        ),
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (_, s) {
            final duration = player.duration ?? Duration.zero;
            final pos = s.data ?? Duration.zero;
            final max = duration.inMilliseconds.toDouble();
            return Row(
              children: [
                Text(clock(pos), style: const TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: pos.inMilliseconds
                        .toDouble()
                        .clamp(0.0, max > 0 ? max : 1)
                        .toDouble(),
                    max: max > 0 ? max : 1,
                    onChanged: max > 0
                        ? (v) => player.seek(Duration(milliseconds: v.round()))
                        : null,
                  ),
                ),
                Text(clock(duration), style: const TextStyle(fontSize: 11)),
              ],
            );
          },
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (_, child) => Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: accent),
            SizedBox(width: 10),
            Text(
              'ritmo',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar yt-dlp',
            onPressed: library.active ? null : library.updateEngine,
            icon: const Icon(Icons.system_update_alt),
          ),
          IconButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Ritmo',
              applicationVersion: '1.4.0 · Spotify + YouTube',
              children: [
                const Text(
                  'Motor yt-dlp + FFmpeg incluido. Mantén Ritmo abierta durante la descarga. Playlists propias y música del teléfono.\n\nLas descargas internas se borran al desinstalar. Usa Guardar en carpeta para conservarlas.\n\nDescarga contenido propio o autorizado.',
                ),
              ],
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: switch (tab) {
                0 => downloadsPage(),
                1 => savedPage(),
                2 => playlistsPage(),
                _ => devicePage(),
              },
            ),
            if (playing != null) miniPlayer(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() {
          tab = v;
          search.clear();
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.downloading),
            label: 'Descargar',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            label: 'Guardado',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music),
            label: 'Playlists',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: 'Teléfono',
          ),
        ],
      ),
    ),
  );
}

class PlaylistPage extends StatefulWidget {
  final Downloads library;
  final MusicPlaylist playlist;
  final Future<void> Function(List<Track>, int) play;
  const PlaylistPage({
    super.key,
    required this.library,
    required this.playlist,
    required this.play,
  });
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  Downloads get library => widget.library;
  MusicPlaylist get p => widget.playlist;
  Future<void> handle(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> chooseSongs() async {
    final all = [...library.saved, ...library.deviceTracks];
    final selected = <String>{};
    String query = '';
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final shown = all
              .where(
                (t) => '${t.title} ${t.author}'.toLowerCase().contains(
                  query.toLowerCase(),
                ),
              )
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(c).height * .75,
              child: Column(
                children: [
                  const Text(
                    'Añadir canciones',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar canción',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => update(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: all.isEmpty
                        ? const Center(
                            child: Text(
                              'Descarga canciones o explora la sección Teléfono.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final t = shown[i];
                              final exists = p.trackIds.contains(t.id);
                              return CheckboxListTile(
                                value: exists || selected.contains(t.id),
                                title: Text(t.title, maxLines: 2),
                                subtitle: Text(
                                  t.device
                                      ? 'Del teléfono'
                                      : 'Descarga de Ritmo',
                                ),
                                onChanged: exists
                                    ? null
                                    : (v) => update(() {
                                        if (v == true) {
                                          selected.add(t.id);
                                        } else {
                                          selected.remove(t.id);
                                        }
                                      }),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text('Añadir ${selected.length} canciones'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == true) {
      await handle(
        () =>
            library.addToPlaylist(p, all.where((t) => selected.contains(t.id))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (_, child) {
      final playable = library.playableList(p);
      return Scaffold(
        appBar: AppBar(
          title: Text(p.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final name = await askName(
                    context,
                    'Renombrar playlist',
                    p.name,
                  );
                  if (name != null) {
                    await handle(() => library.renamePlaylist(p, name));
                  }
                }
                if (v == 'delete') {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('¿Eliminar playlist?'),
                      content: const Text('Las canciones se conservan.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) {
                    await handle(() async {
                      await library.deletePlaylist(p);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    });
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Eliminar playlist'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: playable.isEmpty
                          ? null
                          : () => widget.play(playable, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Reproducir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: chooseSongs,
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir canciones'),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Arrastra el control de cada canción para cambiar el orden.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: p.trackIds.isEmpty
                    ? const Center(child: Text('Esta playlist aún está vacía.'))
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: p.trackIds.length,
                        onReorder: (a, b) =>
                            handle(() => library.moveInPlaylist(p, a, b)),
                        itemBuilder: (_, i) {
                          final id = p.trackIds[i];
                          final t = library.lookup(id);
                          final available = t?.playable == true;
                          return ListTile(
                            key: ValueKey(id),
                            leading: ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle),
                            ),
                            title: Text(
                              t?.title ?? 'Archivo no disponible',
                              maxLines: 2,
                            ),
                            subtitle: Text(
                              t == null
                                  ? 'Vuelve a explorar Teléfono o quita esta referencia'
                                  : t.device
                                  ? 'Del teléfono'
                                  : 'Descarga de Ritmo',
                            ),
                            onTap: available
                                ? () => widget.play(
                                    playable,
                                    playable.indexWhere((x) => x.id == id),
                                  )
                                : null,
                            trailing: IconButton(
                              onPressed: () => handle(
                                () => library.removeFromPlaylist(p, id),
                              ),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
