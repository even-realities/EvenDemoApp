import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:demo_ai_even/services/local_file_service.dart';
import 'package:demo_ai_even/services/subtitle_parser.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

  @override
  void dispose() {
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
    setState(() { _subtitlePath = path; _cues = cues; _activeIndex = -1; });
  }

  Future<void> _start() async {
    if (_audioPath == null || _cues.isEmpty) return;
    await _player.play(DeviceFileSource(_audioPath!));
    _player.onPositionChanged.listen((pos) {
      _syncTo(pos);
    });
  }

  void _syncTo(Duration pos) async {
    if (_cues.isEmpty) return;
    // Find active cue
    final i = _cues.indexWhere((c) => pos >= c.start && pos <= c.end);
    if (i != -1 && i != _activeIndex) {
      setState(() { _activeIndex = i; });
      if (_sendToDevice) {
        final text = _cues[i].text;
        // send as a short overlay
        await Proto.sendEvenAIData(
          text,
          newScreen: EvenAIDataMethod.transferToNewScreen(0x01, 0x50),
          pos: 0,
          current_page_num: 1,
          max_page_num: 1,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('オーディオブックビューワー')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(_audioPath ?? '音声ファイルを選択')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickAudio, child: const Text('音声選択')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(_subtitlePath ?? '字幕ファイル（.srt/.vtt）を選択')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickSubtitle, child: const Text('字幕選択')),
              ],
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Expanded(
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
      ),
    );
  }
}
