import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:demo_ai_even/services/local_file_service.dart';
import 'package:demo_ai_even/services/subtitle_parser.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/media_gateway_service.dart';
import 'package:demo_ai_even/services/controller_events.dart';
import 'package:demo_ai_even/services/input_mapping_service.dart';
import 'package:demo_ai_even/services/silent_audio_keeper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AudiobookViewerPage extends StatefulWidget {
  const AudiobookViewerPage({super.key});

  @override
  State<AudiobookViewerPage> createState() => _AudiobookViewerPageState();
}

class _AudiobookViewerPageState extends State<AudiobookViewerPage> {
  final AudioPlayer _player = AudioPlayer();
  List<SubtitleCue> _cues = [];
  String? _audioPath;
  String? _subtitlePath;
  int _activeIndex = -1;
  bool _sendToDevice = true;
  bool _viewerMode = false; // playback-focused UI mode
  // legacy scraping UI fields (removed)

  // Media Gateway API integration
  final TextEditingController _gatewayBase = TextEditingController(text: 'http://100.67.175.96:8010');
  final TextEditingController _gatewayToken = TextEditingController();
  final TextEditingController _gatewayUser = TextEditingController();
  final TextEditingController _gatewayPass = TextEditingController();
  GatewayAuth _authMode = GatewayAuth.none;
  bool _loadingRoots = false;
  bool _loadingEntries = false;
  List<String> _roots = [];
  String? _selectedRoot;
  String _currentPath = '/';
  List<GatewayEntry> _entries = [];
  bool _downloading = false;
  double _downloadProgress = 0.0;
  int _lastSubtitleSendMs = 0;
  String? _lastSubtitleSent;

  // playback state
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  double _speed = 1.0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<Map<String, dynamic>>? _controllerSub;
  StreamSubscription<Map<String, dynamic>>? _remoteSub;
  final InputMappingService _mapping = InputMappingService.instance;
  Timer? _pollTimer; // BG-safe polling fallback
  Duration? _lastPolled;
  bool _bgKeepAudio = false; // 開発専用: 無音ループでBG維持

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _controllerSub?.cancel();
    _remoteSub?.cancel();
    _pollTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3','m4a','aac','wav']);
    if (res == null) return;
    setState(() { _audioPath = res.files.single.path; });
  }

  Future<void> _pickSubtitle() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['srt','vtt']);
    if (res == null) return;
    final path = res.files.single.path;
    if (path == null) return;
    final content = await File(path).readAsString();
    final cues = SubtitleParser.parse(content, extension: path);
    debugPrint('[Audiobook] Picked subtitle file: $path, cues=${cues.length}');
    setState(() { _subtitlePath = path; _cues = cues; _activeIndex = -1; });
  }

  // legacy scraping code removed

  // ===== Media Gateway helpers =====
  void _applyGatewayConfig() {
    final svc = MediaGatewayService.instance;
    svc.baseUrl = _gatewayBase.text.trim();
    svc.auth = _authMode;
    switch (_authMode) {
      case GatewayAuth.none:
        svc.token = null;
        svc.username = null;
        svc.password = null;
        break;
      case GatewayAuth.bearer:
        svc.token = _gatewayToken.text.trim();
        svc.username = null;
        svc.password = null;
        break;
      case GatewayAuth.basic:
        svc.token = null;
        svc.username = _gatewayUser.text.trim();
        svc.password = _gatewayPass.text;
        break;
    }
  }

  Future<void> _loadRoots() async {
    _applyGatewayConfig();
    setState(() { _loadingRoots = true; });
    try {
      final roots = await MediaGatewayService.instance.getRoots();
      setState(() {
        _roots = roots;
        if (roots.isNotEmpty && (_selectedRoot == null || !_roots.contains(_selectedRoot))) {
          _selectedRoot = roots.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ルート取得失敗: $e')));
    } finally {
      setState(() { _loadingRoots = false; });
    }
  }

  Future<void> _listEntries({String? path}) async {
    if (_selectedRoot == null) return;
    if (path != null) _currentPath = path;
    _applyGatewayConfig();
    setState(() { _loadingEntries = true; });
    try {
      final list = await MediaGatewayService.instance.list(root: _selectedRoot!, path: _currentPath);
      // keep only dirs, audio, subtitles
      final filtered = list.where((e) => e.isDir || _isAudio(e) || _isSubtitle(e)).toList();
      setState(() { _entries = filtered; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('一覧取得失敗: $e')));
    } finally {
      setState(() { _loadingEntries = false; });
    }
  }

  String _parentPath(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return '/';
    segs.removeLast();
    return segs.isEmpty ? '/' : '/${segs.join('/')}';
  }

  bool _isAudio(GatewayEntry e) {
    final ext = (e.ext.isNotEmpty ? e.ext : e.name.split('.').length > 1 ? '.${e.name.split('.').last}' : '').toLowerCase();
    return ext == '.mp3' || ext == '.m4a' || ext == '.aac' || ext == '.wav';
  }

  bool _isSubtitle(GatewayEntry e) {
    final ext = (e.ext.isNotEmpty ? e.ext : e.name.split('.').length > 1 ? '.${e.name.split('.').last}' : '').toLowerCase();
    return ext == '.srt' || ext == '.vtt';
  }

  String _extFrom(GatewayEntry e) {
    final ext = (e.ext.isNotEmpty ? e.ext : e.name.split('.').length > 1 ? '.${e.name.split('.').last}' : '').toLowerCase();
    return ext;
  }

  String _baseName(GatewayEntry e) {
    final ext = _extFrom(e);
    final lowerName = e.name;
    if (ext.isNotEmpty && lowerName.toLowerCase().endsWith(ext)) {
      return lowerName.substring(0, lowerName.length - ext.length);
    }
    final idx = lowerName.lastIndexOf('.');
    return idx > 0 ? lowerName.substring(0, idx) : lowerName;
  }

  Future<void> _downloadViaGateway({required GatewayEntry entry}) async {
    if (_selectedRoot == null) return;
    setState(() { _downloading = true; _downloadProgress = 0; });
    try {
      // if already exists, short-circuit and set path
      final exists = await MediaGatewayService.instance.existsLocally(root: _selectedRoot!, filePath: entry.path);
      if (exists) {
        final p = await MediaGatewayService.instance.resolveLocalPath(root: _selectedRoot!, filePath: entry.path);
        if (_isAudio(entry)) {
          setState(() { _audioPath = p; });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('既にダウンロード済み（再DLなし）')));
        } else if (_isSubtitle(entry)) {
          final content = await File(p).readAsString();
          final cues = SubtitleParser.parse(content, extension: p);
          setState(() { _subtitlePath = p; _cues = cues; _activeIndex = -1; });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('既にダウンロード済み（再DLなし）')));
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('既にダウンロード済み')));
        }
        return;
      }

      final savePath = await MediaGatewayService.instance.downloadMediaToDocs(
        root: _selectedRoot!,
        filePath: entry.path,
        onReceiveProgress: (recv, total) {
          if (total > 0) {
            setState(() { _downloadProgress = recv / total; });
          }
        },
      );
      if (_isAudio(entry)) {
        setState(() { _audioPath = savePath; });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音声をダウンロードしました')));
      } else if (_isSubtitle(entry)) {
        final content = await File(savePath).readAsString();
        final cues = SubtitleParser.parse(content, extension: savePath);
        setState(() { _subtitlePath = savePath; _cues = cues; _activeIndex = -1; });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('字幕をダウンロードしました')));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ダウンロード完了: ${entry.name}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ダウンロード失敗: $e')));
    } finally {
      setState(() { _downloading = false; });
    }
  }

  // legacy direct download removed

  // ===== UI helpers =====
  String _relPathOrName(String? absolutePath) {
    if (absolutePath == null || absolutePath.isEmpty) return '';
    final docsIdx = absolutePath.indexOf('/Documents/');
    if (docsIdx >= 0) {
      return absolutePath.substring(docsIdx + '/Documents/'.length);
    }
    final tmpIdx = absolutePath.indexOf('/tmp/');
    if (tmpIdx >= 0) {
      return absolutePath.substring(tmpIdx + '/tmp/'.length);
    }
    // fallback to filename
    final parts = absolutePath.split('/');
    return parts.isNotEmpty ? parts.last : absolutePath;
  }

  Future<void> _start() async {
    if (_audioPath == null || _cues.isEmpty) return;
    // start playback
    debugPrint('[Audiobook] Start playback: file=$_audioPath, cues=${_cues.length}');
    await _player.play(DeviceFileSource(_audioPath!));
    await _player.setPlaybackRate(_speed);
    setState(() { _isPlaying = true; _viewerMode = true; });

    _durSub?.cancel();
    _durSub = _player.onDurationChanged.listen((d) {
      setState(() { _duration = d; });
    });

    _posSub?.cancel();
    _posSub = _player.onPositionChanged.listen((pos) {
      setState(() { _position = pos; });
      _syncTo(pos);
    });

    // Start BG polling fallback if subtitle sending is enabled
    if (_sendToDevice) _startBgPolling();

    // Setup controller mapping on first start if not already
    _controllerSub ??= ControllerEvents().stream.listen((event) {
      final control = event['control'] as String?;
      if (control == null) return;
      final action = _mapping.actionForControl(control);
      _handleMappedAction(action);
    });
    _remoteSub ??= ControllerEvents().remoteStream.listen((event) {
      final control = event['control'] as String?;
      if (control == null) return;
      final action = _mapping.actionForControl(control);
      _handleMappedAction(action);
    });
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() { _isPlaying = false; });
    } else {
      await _player.resume();
      setState(() { _isPlaying = true; });
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    setState(() { _isPlaying = false; _position = Duration.zero; _activeIndex = -1; });
  }

  Future<void> _seekTo(Duration pos) async {
    await _player.seek(pos);
  }

  void _syncTo(Duration pos) async {
    if (_cues.isEmpty) return;
    // Find active cue
    final i = _cues.indexWhere((c) => pos >= c.start && pos <= c.end);
    if (i != -1 && i != _activeIndex) {
      debugPrint('[Audiobook] Cue change: index=$i time=$pos text="${_cues[i].text.replaceAll('\n',' ')}"');
      setState(() { _activeIndex = i; });
      if (_sendToDevice) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastSubtitleSendMs < 900) return; // throttle ~1/sec

        // Wrap to device width and limit lines
        final wrapped = EvenAIDataMethod.measureStringListAdvanced(
          _cues[i].text,
          maxWidth: 488,
          fontSize: 21,
        ).take(3).map((e) => '$e\n').join();

        if (wrapped.isEmpty || wrapped == _lastSubtitleSent) return;

        final ok = await Proto.sendEvenAIData(
          wrapped,
          // Use Text Show mode to avoid EvenAI listening UI
          newScreen: EvenAIDataMethod.transferToNewScreen(0x01, 0x70),
          pos: 0,
          current_page_num: 1,
          max_page_num: 1,
        );
        if (ok) {
          _lastSubtitleSendMs = now;
          _lastSubtitleSent = wrapped;
        }
      }
    }
  }

  // Seek helpers
  Future<void> _seekRelative(Duration delta) async {
    // Compute target and clamp to [0, duration] when duration is known
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration.inMilliseconds > 0 && target > _duration) {
      target = _duration;
    }
    await _player.seek(target);
  }

  Future<void> _jumpToCue(int targetIndex) async {
    if (targetIndex < 0 || targetIndex >= _cues.length) return;
    await _player.seek(_cues[targetIndex].start);
  }

  void _jumpToPrevCue() {
    if (_cues.isEmpty) return;
    if (_activeIndex > 0) {
      _jumpToCue(_activeIndex - 1);
      return;
    }
    // find nearest previous by current position
    final pos = _position;
    int idx = -1;
    for (int i = _cues.length - 1; i >= 0; i--) {
      if (_cues[i].start < pos) { idx = i; break; }
    }
    _jumpToCue(idx >= 0 ? idx : 0);
  }

  void _jumpToNextCue() {
    if (_cues.isEmpty) return;
    if (_activeIndex >= 0 && _activeIndex < _cues.length - 1) {
      _jumpToCue(_activeIndex + 1);
      return;
    }
    // find first upcoming by current position
    final pos = _position;
    int idx = -1;
    for (int i = 0; i < _cues.length; i++) {
      if (_cues[i].start > pos) { idx = i; break; }
    }
    if (idx != -1) {
      _jumpToCue(idx);
    }
  }

  void _startBgPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final pos = await _player.getCurrentPosition();
        if (pos == null) return;
        // Reduce redundant syncs
        if (_lastPolled != null && (pos - _lastPolled!).abs() < const Duration(milliseconds: 400)) return;
        _lastPolled = pos;
        _position = pos;
        _syncTo(pos);
      } catch (_) {}
    });
  }

  void _stopBgPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // Map ReaderAction (from InputMappingService) to Audiobook actions
  void _handleMappedAction(ReaderAction? action) {
    switch (action) {
      case ReaderAction.nextPage:
        _jumpToNextCue();
        break;
      case ReaderAction.previousPage:
        _jumpToPrevCue();
        break;
      case ReaderAction.autoScrollStart:
        // Use as Play/Resume
        if (!_isPlaying) { _togglePlayPause(); }
        break;
      case ReaderAction.autoScrollStop:
        // Use as Pause
        if (_isPlaying) { _togglePlayPause(); }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('オーディオブックビューワー'),
        actions: [
          if (_viewerMode)
            IconButton(
              tooltip: 'ビュー解除',
              onPressed: () => setState(() => _viewerMode = false),
              icon: const Icon(Icons.close_fullscreen),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double mediaListHeight = (constraints.maxHeight * 0.28).clamp(120.0, 260.0);
          final double cuesHeight = (constraints.maxHeight * 0.28).clamp(120.0, 260.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            // ===== Media Gateway API section =====
            if (!_viewerMode)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Media Gateway (API) 経由で取得', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _gatewayBase, decoration: const InputDecoration(labelText: 'ベースURL（例: http://<IP>:8000）'))),
                    const SizedBox(width: 8),
                    DropdownButton<GatewayAuth>(
                      value: _authMode,
                      items: const [
                        DropdownMenuItem(value: GatewayAuth.none, child: Text('認証なし')),
                        DropdownMenuItem(value: GatewayAuth.bearer, child: Text('Bearer')),
                        DropdownMenuItem(value: GatewayAuth.basic, child: Text('Basic')),
                      ],
                      onChanged: (v) => setState(() => _authMode = v ?? GatewayAuth.none),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _loadingRoots ? null : _loadRoots, child: const Text('Roots取得')),
                  ]),
                  if (_authMode == GatewayAuth.bearer) ...[
                    const SizedBox(height: 8),
                    TextField(controller: _gatewayToken, decoration: const InputDecoration(labelText: 'Bearer Token')), 
                  ]
                  else if (_authMode == GatewayAuth.basic) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: _gatewayUser, decoration: const InputDecoration(labelText: 'ユーザー名'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _gatewayPass, decoration: const InputDecoration(labelText: 'パスワード'), obscureText: true)),
                    ]),
                  ],
                  if (_loadingRoots) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedRoot,
                  hint: const Text('Root を選択'),
                  items: _roots.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) async {
                    setState(() { _selectedRoot = v; _currentPath = '/'; });
                    await _listEntries(path: '/');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '上へ',
                onPressed: (_selectedRoot == null || _currentPath == '/') ? null : () async {
                  final parent = _parentPath(_currentPath);
                  await _listEntries(path: parent);
                },
                icon: const Icon(Icons.arrow_upward),
              ),
              const SizedBox(width: 4),
              ElevatedButton(onPressed: (_selectedRoot == null || _loadingEntries) ? null : () => _listEntries(), child: const Text('一覧取得')),
            ]),
                  if (_loadingEntries) const LinearProgressIndicator(),
                  if (_downloading) Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: LinearProgressIndicator(value: _downloadProgress == 0 ? null : _downloadProgress),
                  ),
                  if (_entries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: mediaListHeight,
                      child: Builder(
                        builder: (context) {
                          // Separate directories and files
                          final dirs = _entries.where((e) => e.isDir).toList()
                            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                          final files = _entries.where((e) => !e.isDir).toList();

                          // Group files by base name (name without extension)
                          final Map<String, Map<String, GatewayEntry>> groups = {};
                          for (final f in files) {
                            final base = _baseName(f);
                            final kind = _isAudio(f) ? 'audio' : (_isSubtitle(f) ? 'subtitle' : 'other');
                            if (kind == 'other') continue;
                            groups.putIfAbsent(base, () => {});
                            // keep first occurrence if duplicate
                            groups[base]![kind] ??= f;
                          }

                          final bases = groups.entries
                              .where((e) => e.value.containsKey('audio') && e.value.containsKey('subtitle'))
                              .map((e) => e.key)
                              .toList()
                            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                          final tiles = <Widget>[];

                          // Directories first
                          for (final e in dirs) {
                            tiles.add(Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.folder),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(onPressed: () async { await _listEntries(path: e.path); }, icon: const Icon(Icons.chevron_right)),
                                ],
                              ),
                            ));
                          }

                          // Then grouped base names with audio/subtitle side-by-side
                          for (final base in bases) {
                            final audio = groups[base]!['audio'];
                            final sub = groups[base]!['subtitle'];
                            // choose a representative path to show (audio then sub)
                            final showPath = audio?.path ?? sub?.path ?? '';
                            tiles.add(Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(audio != null ? Icons.audiotrack : Icons.subtitles),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(base, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(showPath, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (audio != null)
                                    OutlinedButton(onPressed: () => _downloadViaGateway(entry: audio), child: const Text('DL音声')),
                                  if (sub != null) ...[
                                    const SizedBox(width: 6),
                                    OutlinedButton(onPressed: () => _downloadViaGateway(entry: sub), child: const Text('DL字幕')),
                                  ],
                                ],
                              ),
                            ));
                          }

                          return ListView(children: tiles);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (!_viewerMode)
            Row(
              children: [
                Expanded(child: Text(_relPathOrName(_audioPath).isEmpty ? '音声ファイルを選択' : _relPathOrName(_audioPath), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickAudio, child: const Text('音声選択')),
              ],
            ),
            const SizedBox(height: 8),
            if (!_viewerMode)
            Row(
              children: [
                Expanded(child: Text(_relPathOrName(_subtitlePath).isEmpty ? '字幕ファイル（.srt/.vtt）を選択' : _relPathOrName(_subtitlePath), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickSubtitle, child: const Text('字幕選択')),
              ],
            ),
            const SizedBox(height: 12),
            // BG維持（無音ループ）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('BG維持(開発専用)'),
                Switch(
                  value: _bgKeepAudio,
                  onChanged: (v) async {
                    setState(() => _bgKeepAudio = v);
                    if (v) {
                      await SilentAudioKeeper.instance.start();
                    } else {
                      await SilentAudioKeeper.instance.stop();
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                ElevatedButton(onPressed: _start, child: const Text('再生')),
                const SizedBox(width: 12),
                Row(
                  children: [
                    const Text('グラスに字幕送信'),
                    Switch(value: _sendToDevice, onChanged: (v){ setState(() => _sendToDevice = v); }),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // playback controls
            Row(
              children: [
                Text(_fmt(_position)),
                Expanded(
                  child: Slider(
                    value: _duration.inMilliseconds == 0 ? 0 : _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
                    min: 0,
                    max: (_duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds).toDouble(),
                    onChanged: (v) {
                      setState(() { _position = Duration(milliseconds: v.toInt()); });
                    },
                    onChangeEnd: (v) => _seekTo(Duration(milliseconds: v.toInt())),
                  ),
                ),
                Text(_fmt(_duration)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: _cues.isEmpty ? null : _jumpToPrevCue, icon: const Icon(Icons.skip_previous)),
                IconButton(onPressed: (){ _seekRelative(const Duration(seconds: -15)); }, icon: const Icon(Icons.replay_10)),
                IconButton(onPressed: _togglePlayPause, icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled), iconSize: 36),
                IconButton(onPressed: (){ _seekRelative(const Duration(seconds: 30)); }, icon: const Icon(Icons.forward_30)),
                IconButton(onPressed: _cues.isEmpty ? null : _jumpToNextCue, icon: const Icon(Icons.skip_next)),
                const SizedBox(width: 12),
                IconButton(onPressed: () { _stop(); _stopBgPolling(); }, icon: const Icon(Icons.stop_circle)),
                const SizedBox(width: 16),
                DropdownButton<double>(
                  value: _speed,
                  items: const [0.75, 1.0, 1.25, 1.5, 2.0]
                      .map((e) => DropdownMenuItem(value: e, child: Text('${e}x'))).toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() { _speed = v; });
                    await _player.setPlaybackRate(_speed);
                  },
                ),
              ],
            ),
            // prev/next subtitle controls merged into the playback row
            const SizedBox(height: 12),
            // URL指定による取得/ダウンロード（legacy removed）
            /* Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('サーバーから選択（同一ディレクトリのリンクを抽出）'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _serverUrl, decoration: const InputDecoration(labelText: 'ベースURL'))),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _loadingServer ? null : _fetchServer, child: const Text('一覧取得')),
                  ]),
                  if (_loadingServer) const LinearProgressIndicator(),
                  if (_serverItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: _serverItems.length,
                        itemBuilder: (context, i) {
                          final it = _serverItems[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              it.kind == _ItemKind.directory
                                  ? Icons.folder
                                  : it.kind == _ItemKind.audio
                                      ? Icons.audiotrack
                                      : it.kind == _ItemKind.subtitle
                                          ? Icons.subtitles
                                          : Icons.description,
                            ),
                            title: Text(it.name, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              it.kind == _ItemKind.directory
                                  ? 'フォルダ'
                                  : it.kind == _ItemKind.audio
                                      ? '音声'
                                      : it.kind == _ItemKind.subtitle
                                          ? '字幕'
                                          : 'ページ',
                            ),
                            onTap: () async {
                              if (it.kind == _ItemKind.directory || it.kind == _ItemKind.page) {
                                _serverUrl.text = it.url.endsWith('/') ? it.url : (it.url + '/');
                                await _fetchServer();
                              }
                            },
                            trailing: Wrap(spacing: 8, children: [
                              if (it.kind == _ItemKind.audio)
                                OutlinedButton(
                                  onPressed: () { _audioUrl.text = it.url; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音声URLに設定'))); },
                                  child: const Text('音声に設定'),
                                ),
                              if (it.kind == _ItemKind.subtitle)
                                OutlinedButton(
                                  onPressed: () { _subtitleUrl.text = it.url; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('字幕URLに設定'))); },
                                  child: const Text('字幕に設定'),
                                ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _audioUrl, decoration: const InputDecoration(labelText: '音声URL'))),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () async {
                      final p = await _downloadToLocal(_audioUrl.text.trim());
                      if (p != null) setState(() => _audioPath = p);
                    }, child: const Text('DL')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _subtitleUrl, decoration: const InputDecoration(labelText: '字幕URL（.srt/.vtt）'))),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () async {
                      final p = await _downloadToLocal(_subtitleUrl.text.trim());
                      if (p != null) {
                        final content = await File(p).readAsString();
                        final cues = SubtitleParser.parse(content, extension: p);
                        setState(() { _subtitlePath = p; _cues = cues; _activeIndex = -1; });
                      }
                    }, child: const Text('DL')),
                  ]),
                ],
              ),
            ),*/
            // Remove legacy scraping block entirely
            const SizedBox(height: 12),
            SizedBox(
              height: cuesHeight,
              child: ListView.builder(
                itemCount: _cues.length,
                itemBuilder: (context, index) {
                  final c = _cues[index];
                  final active = index == _activeIndex;
                  return ListTile(
                    dense: true,
                    title: Text(c.text),
                    subtitle: Text('${c.start} - ${c.end}'),
                    tileColor: active ? Colors.amber.withOpacity(0.2) : null,
                  );
                },
              ),
            ),
          ],
        ),
      );
        },
      ),
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
