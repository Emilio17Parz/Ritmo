import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'downloads.dart';
import 'music_match.dart';
import 'spotify_client.dart';
import 'spotify_build_config.dart';

class SpotifyPage extends StatefulWidget {
  final Downloads library;
  final String? sourceLink;
  const SpotifyPage({super.key, required this.library, this.sourceLink});
  @override
  State<SpotifyPage> createState() => _SpotifyPageState();
}

class _SpotifyPageState extends State<SpotifyPage> {
  late final TextEditingController clientId;
  Downloads get library => widget.library;
  @override
  void initState() {
    super.initState();
    clientId = TextEditingController(text: library.spotify.clientId);
    if (widget.sourceLink != null) {
      library.spotifyRows.clear();
      library.spotifyName = '';
      library.spotifySkipped = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) run(processLink);
      });
    }
  }

  @override
  void dispose() {
    clientId.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('FormatException: ', '')),
          ),
        );
    }
  }

  Future<void> processLink() async {
    if (library.active) return;
    if (!library.spotify.connected) {
      if (clientId.text.trim().isEmpty) {
        throw SpotifyProblem(
          'Configura tu Client ID para conectar Spotify una vez.',
        );
      }
      await library.configureSpotify(clientId.text);
      await library.connectSpotify(
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
      );
    }
    if (!mounted || !library.spotify.connected || widget.sourceLink == null)
      return;
    await library.importSpotify(widget.sourceLink!);
  }

  Future<void> choose(SpotifyMatchRow row) async {
    final choice = await showModalBottomSheet<VideoMatch>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * .75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Elegir versión de YouTube',
                style: Theme.of(c).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('${row.song.title} · ${row.song.artist}'),
            ),
            Expanded(
              child: ListView(
                children: row.candidates
                    .map(
                      (v) => ListTile(
                        title: Text(v.title),
                        subtitle: Text(
                          '${v.author}\n${duration(v.duration)} · ${v.confident ? "Coincidencia sugerida" : "Revisa la versión"}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Abrir en YouTube',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => launchUrl(
                            Uri.https('www.youtube.com', '/watch', {'v': v.id}),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        onTap: () => Navigator.pop(c, v),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice != null) library.selectSpotifyMatch(row, choice);
  }

  String duration(double seconds) => seconds <= 0
      ? 'Duración no disponible'
      : '${seconds ~/ 60}:${(seconds.toInt() % 60).toString().padLeft(2, '0')}';
  void detail() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Detalle técnico'),
      content: SingleChildScrollView(child: SelectableText(library.lastDetail)),
      actions: [
        TextButton(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: library.lastDetail)),
          child: const Text('Copiar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (_, child) {
      final selected = library.spotifyRows
          .where((r) => r.selected != null)
          .length;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.sourceLink == null
                ? 'Ajustes de Spotify'
                : 'Revisar canciones',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Tu música, también aquí',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Leemos los nombres en Spotify, buscamos versiones en YouTube y las añadimos a tu cola. Revisa las coincidencias antes de descargar.',
              ),
              const SizedBox(height: 20),
              ExpansionTile(
                initiallyExpanded: !library.spotify.connected,
                title: Text(
                  library.spotify.connected
                      ? 'Spotify conectado'
                      : 'Conectar Spotify',
                ),
                childrenPadding: const EdgeInsets.all(12),
                children: [
                  TextField(
                    controller: clientId,
                    enabled: !library.active && spotifyBuildClientId.isEmpty,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Client ID de Spotify',
                      helperText: spotifyBuildClientId.isEmpty
                          ? 'No introduzcas el Client Secret.'
                          : 'Incluido al compilar esta aplicación.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Configura esta Redirect URI en Spotify for Developers:',
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: SelectableText(
                          SpotifyClient.redirectRegistration,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar dirección',
                        icon: const Icon(Icons.copy),
                        onPressed: () => Clipboard.setData(
                          const ClipboardData(
                            text: SpotifyClient.redirectRegistration,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'En modo desarrollo: dueño con Premium y usuarios autorizados. Spotify puede limitar las playlists a las tuyas o colaborativas.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: library.active
                            ? null
                            : () => run(() async {
                                await library.configureSpotify(clientId.text);
                                await processLink();
                              }),
                        child: const Text('Conectar Spotify'),
                      ),
                      if (library.spotify.connected)
                        TextButton(
                          onPressed: library.active
                              ? null
                              : () => run(() async {
                                  await library.spotify.disconnect();
                                  if (mounted) setState(() {});
                                }),
                          child: const Text('Desconectar'),
                        ),
                    ],
                  ),
                  const Text(
                    'La sesión se guarda cifrada en este teléfono y se renueva automáticamente. Puedes desconectarla aquí.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (widget.sourceLink != null) ...[
                const Text('Enlace recibido desde Descargas'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: library.active ? null : () => run(processLink),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a intentar'),
                ),
              ],
              if (library.active) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                OutlinedButton(
                  onPressed: library.stop,
                  child: const Text('Cancelar'),
                ),
              ],
              const SizedBox(height: 12),
              Text(library.message),
              if (library.lastDetail.isNotEmpty)
                TextButton(onPressed: detail, child: const Text('Ver detalle')),
              if (library.spotifySkipped > 0)
                Text(
                  '${library.spotifySkipped} elementos no disponibles, locales o que no son canciones se omitieron.',
                ),
              if (library.spotifyName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 12),
                  child: Text(
                    library.spotifyName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ...library.spotifyRows.map(
                (row) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: row.selected != null,
                              onChanged:
                                  library.active || row.candidates.isEmpty
                                  ? null
                                  : (checked) {
                                      if (checked == true) {
                                        choose(row);
                                      } else {
                                        library.selectSpotifyMatch(row, null);
                                      }
                                    },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.song.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(row.song.artist),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ver en Spotify',
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => launchUrl(
                                Uri.https(
                                  'open.spotify.com',
                                  '/track/${row.song.id}',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          row.selected == null
                              ? row.error ?? 'Revisa y elige una versión.'
                              : 'YouTube: ${row.selected!.title}',
                        ),
                        if (row.candidates.isNotEmpty)
                          TextButton(
                            onPressed: library.active
                                ? null
                                : () => choose(row),
                            child: const Text('Elegir otra versión'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (library.spotifyRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '$selected seleccionadas · ${library.spotifyRows.length - selected} sin seleccionar',
                ),
                FilledButton.icon(
                  onPressed: library.active || selected == 0
                      ? null
                      : () => run(() async {
                          await library.enqueueSpotify();
                          if (context.mounted) Navigator.pop(context);
                        }),
                  icon: const Icon(Icons.playlist_add),
                  label: Text('Añadir $selected a la cola'),
                ),
                if (library.spotifyPlaylist)
                  const Text(
                    'También se creará una playlist local con las versiones seleccionadas.',
                  ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    },
  );
}
