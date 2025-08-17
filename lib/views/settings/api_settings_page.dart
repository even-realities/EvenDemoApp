import 'dart:convert';
import 'package:demo_ai_even/services/openapi_parser.dart';
import 'package:file_picker/file_picker.dart';

import 'package:demo_ai_even/services/api_client.dart';
import 'package:flutter/material.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController();
  final _path = TextEditingController(text: '/api/endpoint');
  final _headers = TextEditingController(text: '{"Content-Type":"application/json"}');
  final _query = TextEditingController(text: '{}');
  final _textFieldName = TextEditingController(text: 'text');

  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _api.loadConfig();
    setState(() {
      _baseUrl.text = cfg.baseUrl;
      _path.text = cfg.path;
      _headers.text = jsonEncode(cfg.headers);
      _query.text = jsonEncode(cfg.query);
      _textFieldName.text = cfg.textFieldName;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final hdr = (jsonDecode(_headers.text) as Map).cast<String, dynamic>().map((k, v) => MapEntry(k, v.toString()));
      final qry = (jsonDecode(_query.text) as Map).cast<String, dynamic>().map((k, v) => MapEntry(k, v.toString()));
      final cfg = ApiConfig(
        baseUrl: _baseUrl.text.trim(),
        path: _path.text.trim(),
        headers: hdr,
        query: qry,
        textFieldName: _textFieldName.text.trim(),
      );
      await _api.saveConfig(cfg);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗: $e')));
    }
  }

  Future<void> _importOpenApi() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml', 'json'],
      withData: true,
    );
    if (result == null) return;
    final picked = result.files.single;
    final bytes = picked.bytes ?? await picked.xFile.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    SwaggerImportResult parsed;
    if (picked.extension?.toLowerCase() == 'json') {
      parsed = OpenApiParser.fromJson(content);
    } else {
      parsed = OpenApiParser.fromYaml(content);
    }
    setState(() {
      if (parsed.baseUrl != null) _baseUrl.text = parsed.baseUrl!;
      if (parsed.firstPostPath != null) _path.text = parsed.firstPostPath!;
      if (parsed.textFieldName != null) _textFieldName.text = parsed.textFieldName!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API設定')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _importOpenApi,
                  icon: const Icon(Icons.file_open),
                  label: const Text('OpenAPI/Swagger をインポート'),
                ),
              ),
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(labelText: 'Base URL (例: https://example.com)'),
                validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
              ),
              TextFormField(
                controller: _path,
                decoration: const InputDecoration(labelText: 'Path (例: /api/endpoint)'),
                validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
              ),
              TextFormField(
                controller: _textFieldName,
                decoration: const InputDecoration(labelText: 'テキストフィールド名 (例: text)'),
                validator: (v) => (v == null || v.isEmpty) ? '必須です' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _headers,
                decoration: const InputDecoration(labelText: 'Headers JSON (例: {"Authorization":"Bearer ..."})'),
                maxLines: 3,
              ),
              TextFormField(
                controller: _query,
                decoration: const InputDecoration(labelText: 'Query JSON (例: {"lang":"ja"})'),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _save, child: const Text('保存')),
            ],
          ),
        ),
      ),
    );
  }
}
