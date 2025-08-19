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
  final _modelId = TextEditingController(text: 'eleven_v3');
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
      _modelId.text = cfg.modelId;
      _stability = cfg.stability;
      _similarity = cfg.similarityBoost;
      _outputFormat = cfg.outputFormat;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cfg = ElevenLabsConfig(
      apiKey: _apiKey.text.trim(),
      modelId: _modelId.text.trim(),
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
            TextFormField(
              controller: _voiceId,
              decoration: const InputDecoration(labelText: 'Voice ID'),
              validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modelId,
              decoration: const InputDecoration(labelText: 'Model ID (例: eleven_v3, eleven_multilingual_v2)'),
              validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
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
