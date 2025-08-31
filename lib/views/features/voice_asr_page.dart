import 'dart:async';

import 'package:flutter/material.dart';
import 'package:demo_ai_even/services/api_client.dart';
import 'package:demo_ai_even/services/elevenlabs_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/evenai.dart';

class VoiceAsrPage extends StatefulWidget {
  const VoiceAsrPage({super.key});

  @override
  State<VoiceAsrPage> createState() => _VoiceAsrPageState();
}

class _VoiceAsrPageState extends State<VoiceAsrPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ApiClient _api = ApiClient();
  final ElevenLabsService _eleven = ElevenLabsService();
  final AudioPlayer _player = AudioPlayer();
  bool _available = false;
  bool _listening = false;
  bool _useVAD = false;
  bool _outputToGlasses = false;
  String _localeId = 'ja_JP';
  String _partialText = '';
  final StringBuffer _finalBuffer = StringBuffer();
  ApiConfig? _config;
  final List<String> _glassLines = [];
  String _glassesBuffer = '';
  bool _primed = false;
  bool _hasTrailingPartial = false;
  Timer? _partialDebounce;

  @override
  void initState() {
    super.initState();
    // iOSでの再生を安定させるためのオーディオセッション設定
    AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) => setState(() {}),
      onError: (error) => setState(() {}),
    );
    setState(() {
      _available = available;
    });
    if (available) {
      final locales = await _speech.locales();
      final ja = locales.firstWhere(
        (l) => l.localeId.startsWith('ja'),
        orElse: () => locales.first,
      );
      setState(() {
        _localeId = ja.localeId;
      });
    }

    // load API config
    final cfg = await _api.loadConfig();
    setState(() => _config = cfg);
  }

  Future<void> _start() async {
    if (!_available) return;
    setState(() {
      _listening = true;
      _partialText = '';
    });
    // ネイティブの VAD 有効/無効を切替
    const method = MethodChannel('method.bluetooth');
    try {
      await method.invokeMethod('setVADEnabled', {'enabled': _useVAD});
    } catch (_) {}
    await _speech.listen(
      localeId: _localeId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (result) {
        setState(() {
          _partialText = result.recognizedWords;
          if (result.finalResult) {
            final finalized = _partialText.trim();
            if (finalized.isNotEmpty) {
              _finalBuffer.writeln(finalized);
              if (_outputToGlasses) {
                _commitFinalToGlasses(finalized);
              }
            }
            _partialText = '';
            _hasTrailingPartial = false;
          } else {
            if (_outputToGlasses) {
              _debouncedUpdatePartialOnGlasses(_partialText.trim());
            }
          }
        });
      },
    );
  }

  Future<void> _stop() async {
    await _speech.stop();
    setState(() {
      _listening = false;
    });
  }

  void _appendAndRenderToGlasses(String line) {
    if (line.isEmpty) return;
    // バッファに追記し、幅に合わせて行分割
    if (_glassesBuffer.isNotEmpty) {
      _glassesBuffer += '\n';
    }
    _glassesBuffer += line;
    final lines = EvenAIDataMethod.measureStringList(_glassesBuffer);
    _glassLines
      ..clear()
      ..addAll(lines.length <= 5 ? lines : lines.sublist(lines.length - 5));
    _renderGlassesLines();
  }

  void _commitFinalToGlasses(String finalLine) {
    if (finalLine.isEmpty) return;
    if (_hasTrailingPartial && _glassLines.isNotEmpty) {
      // 直近の部分結果を最終結果で置換
      _glassLines[_glassLines.length - 1] = finalLine;
      _hasTrailingPartial = false;
      // finalizedはバッファにも取り込む
      if (_glassesBuffer.isNotEmpty) _glassesBuffer += '\n';
      _glassesBuffer += finalLine;
      _renderGlassesLines();
    } else {
      _appendAndRenderToGlasses(finalLine);
    }
  }

  void _debouncedUpdatePartialOnGlasses(String partial) {
    _partialDebounce?.cancel();
    if (partial.isEmpty) return;
    _partialDebounce = Timer(const Duration(milliseconds: 350), () {
      _updatePartialOnGlasses(partial);
    });
  }

  void _updatePartialOnGlasses(String partial) {
    if (partial.isEmpty) return;
    // 部分結果は最後の行として一時的に表示（次の確定で置換）
    if (_glassLines.isEmpty) {
      _glassLines.add(partial);
      _hasTrailingPartial = true;
    } else if (_hasTrailingPartial) {
      _glassLines[_glassLines.length - 1] = partial;
    } else {
      _glassLines.add(partial);
      _hasTrailingPartial = true;
      // バッファは確定時にのみ積み増し
    }
    // 最新5行だけ保持
    if (_glassLines.length > 5) {
      _glassLines.removeRange(0, _glassLines.length - 5);
    }
    _renderGlassesLines();
  }

  Future<void> _renderGlassesLines() async {
    final text = _glassLines.map((e) => '$e\n').join();
    if (text.trim().isEmpty) return;
    try {
      // Text Showモードで常に表示（EvenAI listening UIを避ける）
      final ok = await Proto.sendEvenAIData(
        text,
        newScreen: EvenAIDataMethod.transferToNewScreen(0x01, 0x70),
        pos: 0,
        current_page_num: 1,
        max_page_num: 1,
      );
      if (!ok && mounted) {
        Fluttertoast.showToast(msg: 'グラス送信失敗（未接続/タイムアウト）');
      }
    } catch (_) {}
  }

  Future<void> _primeGlassesDisplay() async {
    // 先頭に少しマージンを入れたい場合は空行を追加
    if (_glassesBuffer.isEmpty) {
      _glassesBuffer = '\n';
    }
    _primed = false;
    await _renderGlassesLines();
  }

  Future<void> _sendAllText() async {
    final cfg = _config;
    if (cfg == null) return;
    final text = _finalBuffer.toString().trim();
    if (text.isEmpty) {
      Fluttertoast.showToast(msg: '送信するテキストがありません');
      return;
    }
    try {
      final resp = await _api.postText(config: cfg, text: text);
      Fluttertoast.showToast(msg: '送信成功: ${resp.statusCode}');
    } catch (e) {
      Fluttertoast.showToast(msg: '送信失敗: $e');
    }
  }

  Future<void> _sendToElevenLabs() async {
    final text = _finalBuffer.toString().trim();
    if (text.isEmpty) {
      Fluttertoast.showToast(msg: '送信するテキストがありません');
      return;
    }
    final cfg = await _eleven.loadConfig();
    if (cfg.apiKey.isEmpty || cfg.voiceId.isEmpty) {
      Fluttertoast.showToast(msg: 'ElevenLabs設定が未入力です');
      return;
    }
    try {
      final resp = await _eleven.synthesize(config: cfg, text: text);
      if (resp.statusCode == 200 && resp.data != null && resp.data!.isNotEmpty) {
        Fluttertoast.showToast(msg: 'ElevenLabs送信成功（再生開始）');
        // mp3のmimeTypeを明示し、iOSのデコーダにヒントを与える
        await _player.play(BytesSource(resp.data!, mimeType: 'audio/mpeg'));
      } else {
        Fluttertoast.showToast(msg: 'ElevenLabs送信失敗: ${resp.statusCode}');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'ElevenLabsエラー: $e');
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fullText = _finalBuffer.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('音声認識（iOS ASR）')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('ロケール: $_localeId', overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  color: _listening ? Colors.red : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    [fullText, if (_partialText.isNotEmpty) '$_partialText…'].where((e) => e.isNotEmpty).join('\n'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('VAD'),
                    Switch(
                      value: _useVAD,
                      onChanged: (v) {
                        setState(() => _useVAD = v);
                        // TODO: MethodChannelでネイティブに反映する
                      },
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('グラスへ出力'),
                  Switch(
                    value: _outputToGlasses,
                    onChanged: (v) {
                      setState(() => _outputToGlasses = v);
                      if (v) {
                        _primeGlassesDisplay();
                      }
                    },
                  ),
                ],
              ),
                ElevatedButton(
                  onPressed: _listening ? null : _start,
                  child: const Text('開始'),
                ),
                ElevatedButton(
                  onPressed: _listening ? _stop : null,
                  child: const Text('停止'),
                ),
                ElevatedButton(
                  onPressed: _sendAllText,
                  child: const Text('API送信'),
                ),
                ElevatedButton(
                  onPressed: _sendToElevenLabs,
                  child: const Text('ElevenLabsへ送信'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _finalBuffer.clear();
                      _partialText = '';
                    });
                  },
                  child: const Text('クリア'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
