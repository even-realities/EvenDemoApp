
import 'dart:io';
import 'dart:convert';

import 'package:demo_ai_even/services/local_file_service.dart';
import 'package:demo_ai_even/views/features/text_viewer_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class CustomTextReaderPage extends StatefulWidget {
  const CustomTextReaderPage({super.key});

  @override
  State<CustomTextReaderPage> createState() => _CustomTextReaderPageState();
}

class _CustomTextReaderPageState extends State<CustomTextReaderPage> {
  bool _isLoading = true;
  List<String> _fileList = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });
    final files = await LocalFileService.instance.listFiles();
    setState(() {
      _fileList = files;
      _isLoading = false;
    });
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // .txt/.md/.markdown を許可
        allowedExtensions: ['txt', 'md', 'markdown'],
        withData: true, // iCloud等の仮想ファイルに備えバイトを同時取得
      );

      if (result != null) {
        final picked = result.files.single;
        final fileName = picked.name;
        String content;
        try {
          if (picked.bytes != null) {
            // iCloudなどサンドボックス外のファイルでもサムネやインボックスコピー不要で読める
                    content = utf8.decode(picked.bytes!, allowMalformed: true);
          } else if (picked.path != null) {
            // ローカルに実体がある場合はパスから読む
            content = await File(picked.path!).readAsString();
          } else {
            throw Exception('ファイル内容にアクセスできません');
          }
        } catch (e) {
          throw Exception('ファイル読み込みに失敗: $e');
        }

        await LocalFileService.instance.saveFile(fileName, content);
        await _loadFiles(); // リストを再読み込み

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$fileName をインポートしました')),
        );
      } else {
        // ユーザーがピッカーをキャンセルした場合
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ファイルの読み込みに失敗しました: $e')),
      );
    }
  }

  Future<void> _deleteFile(String fileName) async {
    await LocalFileService.instance.deleteFile(fileName);
    await _loadFiles();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$fileName を削除しました')),
    );
  }

  void _navigateToViewer(String fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TextViewerPage(fileName: fileName),
      ),
    ).then((_) => _loadFiles()); // 閲覧画面から戻ってきたらリストを更新する可能性を考慮
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('カスタムテキストリーダー'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFiles,
            tooltip: 'リストを更新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _fileList.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'ファイルがありません。下のプラスボタンからテキストファイル(.txt)を追加してください。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _fileList.length,
                  itemBuilder: (context, index) {
                    final fileName = _fileList[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: ListTile(
                        title: Text(fileName),
                        onTap: () => _navigateToViewer(fileName),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteFile(fileName),
                          tooltip: '削除',
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        tooltip: 'テキストファイルを追加',
        child: const Icon(Icons.add),
      ),
    );
  }
}
