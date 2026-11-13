import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

const mediaChannel = MethodChannel('opentune/media');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final handler = await AudioService.init(
    builder: OpenTuneAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.opentune.playback',
      androidNotificationChannelName: 'OpenTune playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(OpenTuneApp(handler: handler));
}

class DeviceTrack {
  const DeviceTrack({required this.id, required this.title, required this.artist,
    required this.album, required this.durationMs, required this.uri, this.artUri});
  final int id, durationMs;
  final String title, artist, album, uri;
  final String? artUri;
  factory DeviceTrack.fromMap(Map<dynamic, dynamic> m) => DeviceTrack(
    id: (m['id'] as num).toInt(),
    title: (m['title'] as String?)?.trim().isNotEmpty == true ? m['title'] as String : 'Unknown title',
    artist: (m['artist'] as String?)?.trim().isNotEmpty == true ? m['artist'] as String : 'Unknown artist',
    album: (m['album'] as String?) ?? 'Unknown album',
    durationMs: (m['duration'] as num?)?.toInt() ?? 0,
    uri: m['uri'] as String,
    artUri: m['artUri'] as String?,
  );
  MediaItem toMediaItem() => MediaItem(
    id: uri, title: title, artist: artist, album: album,
    duration: Duration(milliseconds: durationMs),
    artUri: artUri == null ? null : Uri.tryParse(artUri!),
  );
}

class OpenTuneAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  OpenTuneAudioHandler() {
    player.playbackEventStream.listen((_) => _updateState());
    player.currentIndexStream.listen((i) {
      if (i != null && i >= 0 && i < queue.value.length) mediaItem.add(queue.value[i]);
    });
  }
  void _updateState() {
    final processing = switch (player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(PlaybackState(
      controls: [MediaControl.skipToPrevious,
        player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext, MediaControl.stop],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: const {MediaAction.seek},
      processingState: processing, playing: player.playing,
      updatePosition: player.position, bufferedPosition: player.bufferedPosition,
      speed: player.speed, queueIndex: player.currentIndex,
    ));
  }
  Future<void> loadTracks(List<DeviceTrack> tracks, int start) async {
    final items = tracks.map((t) => t.toMediaItem()).toList();
    queue.add(items);
    await player.setAudioSource(ConcatenatingAudioSource(
      children: tracks.map((t) => AudioSource.uri(Uri.parse(t.uri))).toList(),
    ), initialIndex: start);
    mediaItem.add(items[start]);
    await play();
  }
  @override Future<void> play() => player.play();
  @override Future<void> pause() => player.pause();
  @override Future<void> seek(Duration p) => player.seek(p);
  @override Future<void> skipToNext() async { if (player.hasNext) await player.seekToNext(); }
  @override Future<void> skipToPrevious() async { if (player.hasPrevious) await player.seekToPrevious(); }
  @override Future<void> skipToQueueItem(int i) async {
    if (i >= 0 && i < queue.value.length) await player.seek(Duration.zero, index: i);
  }
  @override Future<void> stop() async { await player.stop(); await super.stop(); }
}

class OpenTuneApp extends StatelessWidget {
  const OpenTuneApp({super.key, required this.handler});
  final OpenTuneAudioHandler handler;
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'OpenTune', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB69CFF))),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB69CFF), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF101014)),
    themeMode: ThemeMode.system, home: LibraryScreen(handler: handler),
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.handler});
  final OpenTuneAudioHandler handler;
  @override State<LibraryScreen> createState() => _LibraryScreenState();
}
class _LibraryScreenState extends State<LibraryScreen> {
  List<DeviceTrack> tracks = [];
  bool scanning = false;
  String? error;
  String query = '';
  int tab = 0;
  @override void initState() { super.initState(); _scan(); }

  Future<void> _scan() async {
    setState(() { scanning = true; error = null; });
    try {
      final sdk = await mediaChannel.invokeMethod<int>('sdkInt') ?? 33;
      final permission = sdk >= 33 ? Permission.audio : Permission.storage;
      final status = await permission.request();
      if (!status.isGranted) throw Exception('Allow music access to scan audio on this device.');
      final raw = await mediaChannel.invokeMethod<List<dynamic>>('scanAudio') ?? [];
      final found = raw.map((x) => DeviceTrack.fromMap(x as Map)).toList();
      if (!mounted) return;
      setState(() { tracks = found; scanning = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString().replaceFirst('Exception: ', ''); scanning = false; });
    }
  }
  Future<void> _play(DeviceTrack track) async {
    try { await widget.handler.loadTracks(tracks, tracks.indexOf(track).clamp(0, tracks.length - 1).toInt()); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playback failed: $e'))); }
  }
  String _time(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final filtered = tracks.where((t) => t.title.toLowerCase().contains(query.toLowerCase()) ||
      t.artist.toLowerCase().contains(query.toLowerCase()) || t.album.toLowerCase().contains(query.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('OpenTune', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: scanning ? null : _scan, icon: const Icon(Icons.refresh), tooltip: 'Rescan')]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search songs, artists, albums',
            filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          _chip('Songs', 0), _chip('Albums', 1), _chip('Artists', 2)])),
        Expanded(child: _body(filtered, c)),
        _playerBar(c),
      ]),
    );
  }
  Widget _chip(String label, int i) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
    label: Text(label), selected: tab == i, onSelected: (_) => setState(() => tab = i)));
  Widget _body(List<DeviceTrack> items, ColorScheme c) {
    if (scanning) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.folder_off_outlined, size: 48),
        Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12),
        FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.refresh), label: const Text('Try again'))])));
    if (tracks.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisSize: MainAxisSize.min, children: [Icon(Icons.library_music, size: 52, color: c.primary),
        const Text('Your library is waiting', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('Add audio files to your device, then scan again.', textAlign: TextAlign.center),
        const SizedBox(height: 12), FilledButton(onPressed: _scan, child: const Text('Scan music'))])));
    if (tab == 1 || tab == 2) {
      final grouped = <String, DeviceTrack>{};
      for (final t in items) { grouped.putIfAbsent(tab == 1 ? t.album : t.artist, () => t); }
      return ListView(children: grouped.entries.map((e) => ListTile(
        leading: CircleAvatar(child: Icon(tab == 1 ? Icons.album : Icons.person)),
        title: Text(e.key), subtitle: Text(tab == 1 ? e.value.artist : 'Artist'),
        trailing: Text('${tracks.where((t) => (tab == 1 ? t.album : t.artist) == e.key).length}'),
        onTap: () => _play(e.value))).toList());
    }
    return ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
      final t = items[i];
      return ListTile(leading: CircleAvatar(backgroundColor: c.surfaceContainerHighest,
        child: Icon(Icons.music_note, color: c.primary)),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(_time(t.durationMs)), onTap: () => _play(t));
    });
  }
  Widget _playerBar(ColorScheme c) => StreamBuilder<MediaItem?>(
    stream: widget.handler.mediaItem, builder: (_, itemSnap) {
      final item = itemSnap.data;
      if (item == null) return const SizedBox.shrink();
      return StreamBuilder<PlaybackState>(stream: widget.handler.playbackState, builder: (_, stateSnap) {
        final isPlaying = stateSnap.data?.playing ?? false;
        return Material(color: c.surfaceContainerHigh, child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.album, color: c.primary, size: 32),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.artist ?? ''),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: widget.handler.skipToPrevious, icon: const Icon(Icons.skip_previous)),
              IconButton(onPressed: isPlaying ? widget.handler.pause : widget.handler.play,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow)),
              IconButton(onPressed: widget.handler.skipToNext, icon: const Icon(Icons.skip_next))])),
          StreamBuilder<Duration>(stream: AudioService.position, builder: (_, pos) {
            final max = (item.duration ?? Duration.zero).inMilliseconds.toDouble();
            final value = (pos.data ?? Duration.zero).inMilliseconds.toDouble().clamp(0, max > 0 ? max : 1);
            return Slider(value: value, max: max > 0 ? max : 1,
              onChanged: (v) => widget.handler.seek(Duration(milliseconds: v.round())));
          }),
        ]));
      });
    });
}
