import 'package:demo_ai_even/services/web_text_extractor.dart';
import 'package:demo_ai_even/services/local_file_service.dart';
import 'package:demo_ai_even/views/features/text_viewer_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WebReaderPage extends StatefulWidget {
  const WebReaderPage({super.key});

  @override
  State<WebReaderPage> createState() => _WebReaderPageState();
}

class _WebReaderPageState extends State<WebReaderPage> {
  final TextEditingController _url = TextEditingController(text: 'http://100.67.175.96:8084/');
  final WebTextExtractor _extractor = WebTextExtractor(Dio());
  WebTextExtractorResult? _result;
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final r = await _extractor.fetchAndExtract(_url.text.trim());
      setState(() { _result = r; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Webテキストリーダー')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _url,
                    decoration: const InputDecoration(labelText: 'URL'),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _loading ? null : _load, child: const Text('取得')),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.open_in_browser),
                  onPressed: () async {
                    final uri = Uri.parse(_url.text.trim());
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text('エラー: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Expanded(
              child: _result == null
                  ? const Center(child: Text('URLを入力して「取得」を押してください'))
                  : ListView(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _result!.title ?? _result!.url,
                                style: Theme.of(context).textTheme.titleLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                // Compose text-only content
                                final buf = StringBuffer();
                                if (_result!.title != null) {
                                  buf.writeln(_result!.title);
                                  buf.writeln('');
                                }
                                for (final t in _result!.textBlocks) {
                                  buf.writeln(t);
                                }
                                if (_result!.textBlocks.isEmpty && _result!.rawTextFallback != null) {
                                  buf.writeln(_result!.rawTextFallback);
                                }
                                final content = buf.toString().trim();
                                if (content.isEmpty) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('送信できるテキストがありません')));
                                  return;
                                }
                                // Save as temp file and open TextViewerPage to reuse sender pipeline
                                final fileName = _safeFileName(_result!.title ?? 'web_text') + '.txt';
                                await LocalFileService.instance.saveFile(fileName, content);
                                if (!mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => TextViewerPage(fileName: fileName)),
                                );
                              },
                              child: const Text('テキストをデバイスへ送信'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_result!.links.isNotEmpty) ...[
                          const Text('リンク', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final l in _result!.links)
                                OutlinedButton(
                                  onPressed: () async {
                                    setState(() { _url.text = l.url; });
                                    await _load();
                                  },
                                  child: Text(l.text, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_result!.textBlocks.isNotEmpty) ...[
                          const Text('本文', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          for (final t in _result!.textBlocks)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(t),
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (_result!.codeBlocks.isNotEmpty) ...[
                          const Text('コード', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          for (final c in _result!.codeBlocks)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(c, style: const TextStyle(fontFamily: 'monospace')),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (_result!.rawTextFallback != null && _result!.textBlocks.isEmpty && _result!.codeBlocks.isEmpty) ...[
                          const Text('全文テキスト', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_result!.rawTextFallback!),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _safeFileName(String name) {
  return name
      .replaceAll(RegExp(r"[^A-Za-z0-9._-]+"), '_')
      .replaceAll(RegExp(r"_+"), '_')
      .replaceAll(RegExp(r"^_+|_+$"), '');
}
