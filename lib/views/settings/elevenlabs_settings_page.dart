import 'package:demo_ai_even/services/elevenlabs_service.dart';
import 'package:flutter/material.dart';

class ElevenLabsSettingsPage extends StatefulWidget {
  const ElevenLabsSettingsPage({super.key});

  @override
  State<ElevenLabsSettingsPage> createState() => _ElevenLabsSettingsPageState();
}

class _ElevenLabsSettingsPageState extends State<ElevenLabsSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  final _voiceId = TextEditingController();
  String? _modelId;
  List<ElevenModel> _models = const [];
  List<ElevenVoice> _voices = const [];
  double _stability = 0.5;
  double _similarity = 0.5;
  String _outputFormat = 'mp3_44100_128';

  final _service = ElevenLabsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _service.loadConfig();
    setState(() {
      _apiKey.text = cfg.apiKey;
      _voiceId.text = cfg.voiceId;
      _modelId = cfg.modelId;
      _stability = cfg.stability;
      _similarity = cfg.similarityBoost;
      _outputFormat = cfg.outputFormat;
    });
    // fetch models/voices if apiKey present
    if (_apiKey.text.isNotEmpty) {
      try {
        final models = await _service.listModels(_apiKey.text.trim());
        final voices = await _service.listVoices(_apiKey.text.trim());
        setState(() {
          _models = models;
          _voices = voices;
          _modelId ??= models.firstWhere((m) => m.id == 'eleven_multilingual_v2', orElse: () => models.first).id;
        });
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cfg = ElevenLabsConfig(
      apiKey: _apiKey.text.trim(),
      modelId: (_modelId ?? 'eleven_multilingual_v2').trim(),
      voiceId: _voiceId.text.trim(),
      stability: _stability,
      similarityBoost: _similarity,
      outputFormat: _outputFormat,
    );
    await _service.saveConfig(cfg);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ElevenLabs 設定'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
          IconButton(
            onPressed: () async {
              if (_apiKey.text.trim().isEmpty) return;
              try {
                final models = await _service.listModels(_apiKey.text.trim());
                final voices = await _service.listVoices(_apiKey.text.trim());
                setState(() {
                  _models = models;
                  _voices = voices;
                  _modelId ??= models.firstWhere((m) => m.id == 'eleven_multilingual_v2', orElse: () => models.first).id;
                });
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取得に失敗しました: $e')));
              }
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'モデル/ボイスを取得',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _apiKey,
              decoration: const InputDecoration(labelText: 'API Key'),
              obscureText: true,
              validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _voices.any((v) => v.id == _voiceId.text) ? _voiceId.text : null,
              items: _voices
                  .map((v) => DropdownMenuItem(
                        value: v.id,
                        child: Text('${v.name}  •  ${v.id}'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _voiceId.text = v ?? _voiceId.text),
              decoration: const InputDecoration(labelText: 'Voice'),
            ),
            TextFormField(
              controller: _voiceId,
              decoration: const InputDecoration(labelText: 'Voice ID（直接入力も可）'),
              validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _modelId ?? 'eleven_multilingual_v2',
              items: (_models.isNotEmpty
                      ? _models
                      : [
                          ElevenModel(id: 'eleven_multilingual_v2', name: 'eleven_multilingual_v2 (recommended)'),
                          ElevenModel(id: 'eleven_v3', name: 'eleven_v3'),
                          ElevenModel(id: 'eleven_flash_v2_5', name: 'eleven_flash_v2_5'),
                          ElevenModel(id: 'eleven_turbo_v2_5', name: 'eleven_turbo_v2_5'),
                        ])
                  .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                  .toList(),
              onChanged: (v) => setState(() => _modelId = v ?? _modelId),
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 12),
            const Text('Stability'),
            Slider(
              value: _stability,
              onChanged: (v) => setState(() => _stability = v),
            ),
            const Text('Similarity Boost'),
            Slider(
              value: _similarity,
              onChanged: (v) => setState(() => _similarity = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _outputFormat,
              items: const [
                DropdownMenuItem(value: 'mp3_44100_128', child: Text('mp3_44100_128')),
                DropdownMenuItem(value: 'mp3_44100_64', child: Text('mp3_44100_64')),
                DropdownMenuItem(value: 'mp3_22050_32', child: Text('mp3_22050_32')),
              ],
              onChanged: (v) => setState(() => _outputFormat = v ?? _outputFormat),
              decoration: const InputDecoration(labelText: 'Output Format'),
            ),
          ],
        ),
      ),
    );
  }
}
