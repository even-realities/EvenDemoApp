
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalFileService {
  // シングルトンインスタンス
  LocalFileService._();
  static final LocalFileService instance = LocalFileService._();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> _getLocalFile(String fileName) async {
    final path = await _localPath;
    return File('$path/$fileName');
  }

  Future<File> saveFile(String fileName, String content) async {
    final file = await _getLocalFile(fileName);
    return file.writeAsString(content);
  }

  Future<String> readFile(String fileName) async {
    try {
      final file = await _getLocalFile(fileName);
      return await file.readAsString();
    } catch (e) {
      return 'Error reading file: $e';
    }
  }

  Future<List<String>> listFiles() async {
    try {
      final path = await _localPath;
      final dir = Directory(path);
      // ディレクトリが存在しない場合があるため確認
      if (!await dir.exists()) {
        return [];
      }
      final files = await dir.list().toList();
      return files
          .map((file) => file.path.split('/').last)
          .where((fileName) {
            final lower = fileName.toLowerCase();
            // .txt と .md/.markdown を対象
            return lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.markdown');
          })
          .toList();
    } catch (e) {
      print('Error listing files: $e');
      return [];
    }
  }

  Future<void> deleteFile(String fileName) async {
    try {
      final file = await _getLocalFile(fileName);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting file: $e');
    }
  }
}
