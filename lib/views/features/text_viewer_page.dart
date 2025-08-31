
import 'package:demo_ai_even/services/custom_text_service.dart';
import 'package:demo_ai_even/services/local_file_service.dart';
import 'package:demo_ai_even/services/controller_events.dart';
import 'package:demo_ai_even/services/input_mapping_service.dart';
import 'package:demo_ai_even/services/silent_audio_keeper.dart';
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
  bool _bgKeepAudio = false; // 開発専用: 無音ループでBG維持
  // new: viewer settings
  double _fontSize = 21.0;
  double _maxWidth = 488.0; // logical width for line wrapping

  @override
  void initState() {
    super.initState();
    _loadFile();
    _textService.onPageChanged = () => setState(() {});

    // ゲームパッドのイベントを購読してトリガーに割り当て
    final mapping = InputMappingService.instance;
    mapping.load();
    ControllerEvents().stream.listen((event) {
      final control = event['control'] as String?;
      if (control == null) return;
      final action = mapping.actionForControl(control);
      _handleAction(action);
    });

    // リモートコマンド（オーディオコントローラ/イヤホン操作）
    ControllerEvents().remoteStream.listen((event) {
      final control = event['control'] as String?;
      if (control == null) return;
      final action = mapping.actionForControl(control);
      _handleAction(action);
    });
  }

  void _handleAction(ReaderAction? action) {
    switch (action) {
      case ReaderAction.nextPage:
        _textService.sendNextPage();
        break;
      case ReaderAction.previousPage:
        _textService.sendPreviousPage();
        break;
      case ReaderAction.autoScrollStart:
        _toggleAutoScroll(true);
        break;
      case ReaderAction.autoScrollStop:
        _toggleAutoScroll(false);
        break;
      default:
        break;
    }
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
    _textService.setupText(content, fontSize: _fontSize, maxWidth: _maxWidth, linesPerPage: 5);
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
                  child: Text(
                    _fileContent,
                    style: TextStyle(fontSize: _fontSize),
                  ),
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
            // font size and text width controls
            Row(
              children: [
                const Text('文字サイズ'),
                Expanded(
                  child: Slider(
                    value: _fontSize,
                    min: 14,
                    max: 30,
                    divisions: 16,
                    label: _fontSize.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _fontSize = v),
                    onChangeEnd: (_) {
                      // optional: re-render preview only; BLE pages still fixed by device renderer
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('1ページ幅'),
                Expanded(
                  child: Slider(
                    value: _maxWidth,
                    min: 360,
                    max: 560,
                    divisions: 20,
                    label: _maxWidth.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _maxWidth = v),
                    onChangeEnd: (_) {
                      // 再ページング：現在のテキストを新しい幅で測り直して送信
                      _textService.applyLayout(fontSize: _fontSize, maxWidth: _maxWidth, fullText: _fileContent);
                      _textService.sendFirstPage();
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('行数/ページ'),
                Expanded(
                  child: Slider(
                    value: _textService.linesPerPage.toDouble(),
                    min: 3,
                    max: 8,
                    divisions: 5,
                    label: _textService.linesPerPage.toString(),
                    onChanged: (v) {
                      // 表示だけ更新（送信はonChangeEndで）
                      setState(() {});
                    },
                    onChangeEnd: (v) {
                      _textService.applyLayout(
                        fontSize: _fontSize,
                        maxWidth: _maxWidth,
                        linesPerPage: v.round(),
                        fullText: _fileContent,
                      );
                      _textService.sendFirstPage();
                    },
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('自動スクロール'),
                Switch(value: _isAutoScroll, onChanged: _toggleAutoScroll),
              ],
            ),
            const SizedBox(height: 8),
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
