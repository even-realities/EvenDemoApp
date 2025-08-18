
import 'package:demo_ai_even/services/custom_text_service.dart';
import 'package:demo_ai_even/services/local_file_service.dart';
import 'package:demo_ai_even/services/controller_events.dart';
import 'package:flutter/material.dart';

class TextViewerPage extends StatefulWidget {
  final String fileName;
  const TextViewerPage({super.key, required this.fileName});

  @override
  State<TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<TextViewerPage> {
  final CustomTextService _textService = CustomTextService();
  String _fileContent = 'Loading...';
  bool _isAutoScroll = false;
  double _scrollSpeed = 8.0;

  @override
  void initState() {
    super.initState();
    _loadFile();
    _textService.onPageChanged = () => setState(() {});

    // ゲームパッドのイベントを購読してトリガーに割り当て
    ControllerEvents().stream.listen((event) {
      final control = event['control'] as String?;
      if (control == null) return;
      switch (control) {
        case 'dpadRight':
        case 'buttonA':
          _textService.sendNextPage();
          break;
        case 'dpadLeft':
        case 'buttonB':
          _textService.sendPreviousPage();
          break;
        case 'dpadUp':
          _toggleAutoScroll(true);
          break;
        case 'dpadDown':
          _toggleAutoScroll(false);
          break;
      }
    });

    // リモートコマンド（オーディオコントローラ/イヤホン操作）
    ControllerEvents().remoteStream.listen((event) {
      final control = event['control'] as String?;
      if (control == null) return;
      switch (control) {
        case 'nextTrack':
          _textService.sendNextPage();
          break;
        case 'previousTrack':
          _textService.sendPreviousPage();
          break;
        case 'play':
        case 'togglePlayPause':
          _toggleAutoScroll(true);
          break;
        case 'pause':
          _toggleAutoScroll(false);
          break;
      }
    });
  }

  @override
  void dispose() {
    _textService.clear();
    super.dispose();
  }

  Future<void> _loadFile() async {
    final content = await LocalFileService.instance.readFile(widget.fileName);
    setState(() {
      _fileContent = content;
    });
    _textService.setupText(content);
    _textService.sendFirstPage();
  }

  void _toggleAutoScroll(bool value) {
    setState(() {
      _isAutoScroll = value;
    });
    if (_isAutoScroll) {
      _textService.startAutoScroll(_scrollSpeed.toInt());
    } else {
      _textService.stopAutoScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: SingleChildScrollView(
                  child: Text(_fileContent),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Page: ${_textService.getCurrentPage()} / ${_textService.getTotalPages()}'),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _textService.sendPreviousPage, child: const Text('前へ')),
                ElevatedButton(onPressed: _textService.sendNextPage, child: const Text('次へ')),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('自動スクロール'),
                Switch(value: _isAutoScroll, onChanged: _toggleAutoScroll),
              ],
            ),
            if (_isAutoScroll)
              Row(
                children: [
                  const Text('速度(秒)'),
                  Expanded(
                    child: Slider(
                      value: _scrollSpeed,
                      min: 2,
                      max: 20,
                      divisions: 18,
                      label: _scrollSpeed.round().toString(),
                      onChanged: (value) {
                        setState(() {
                          _scrollSpeed = value;
                        });
                      },
                      onChangeEnd: (value) {
                        // スライダーの操作が終わったらタイマーを再設定
                        _toggleAutoScroll(true);
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
