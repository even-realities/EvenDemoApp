import 'dart:async';

import 'package:flutter/material.dart';
import 'package:demo_ai_even/services/api_client.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceAsrPage extends StatefulWidget {
  const VoiceAsrPage({super.key});

  @override
  State<VoiceAsrPage> createState() => _VoiceAsrPageState();
}

class _VoiceAsrPageState extends State<VoiceAsrPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ApiClient _api = ApiClient();
  bool _available = false;
  bool _listening = false;
  String _localeId = 'ja_JP';
  String _partialText = '';
  final StringBuffer _finalBuffer = StringBuffer();
  ApiConfig? _config;

  @override
  void initState() {
    super.initState();
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
    await _speech.listen(
      localeId: _localeId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (result) {
        setState(() {
          _partialText = result.recognizedWords;
          if (result.finalResult) {
            _finalBuffer.writeln(_partialText);
            _partialText = '';
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

  @override
  void dispose() {
    _speech.cancel();
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
            Expanded(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
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
