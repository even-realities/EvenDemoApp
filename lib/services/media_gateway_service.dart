import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Authentication modes supported by the Media Gateway
enum GatewayAuth { none, bearer, basic }

class GatewayEntry {
  final String name;
  final String path; // always starts with '/'
  final bool isDir;
  final int? size;
  final double? mtime;
  final String ext;

  GatewayEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.mtime,
    this.ext = '',
  });

  factory GatewayEntry.fromJson(Map<String, dynamic> json) {
    return GatewayEntry(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '/',
      isDir: json['is_dir'] == true,
      size: json['size'] is int ? json['size'] as int : (json['size'] is double ? (json['size'] as double).toInt() : null),
      mtime: json['mtime'] is num ? (json['mtime'] as num).toDouble() : null,
      ext: json['ext']?.toString() ?? '',
    );
  }
}

/// Client for Media Gateway API
class MediaGatewayService {
  MediaGatewayService._();
  static final MediaGatewayService instance = MediaGatewayService._();

  String baseUrl = '';
  GatewayAuth auth = GatewayAuth.none;
  String? token; // for bearer
  String? username; // for basic
  String? password; // for basic

  String _normalizedBase() {
    var b = baseUrl.trim();
    if (b.isEmpty) return '';
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  Map<String, String> _authHeaders() {
    switch (auth) {
      case GatewayAuth.none:
        return {};
      case GatewayAuth.bearer:
        if (token != null && token!.isNotEmpty) {
          return {HttpHeaders.authorizationHeader: 'Bearer ${token!}'};
        }
        return {};
      case GatewayAuth.basic:
        if ((username != null && username!.isNotEmpty) || (password != null && password!.isNotEmpty)) {
          final user = username ?? '';
          final pass = password ?? '';
          final creds = base64Encode('$user:$pass'.codeUnits);
          return {HttpHeaders.authorizationHeader: 'Basic $creds'};
        }
        return {};
    }
  }

  Dio _dio({String? overrideBase}) {
    final headers = _authHeaders();
    return Dio(BaseOptions(
      baseUrl: overrideBase ?? _normalizedBase(),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 2),
      headers: headers.isEmpty ? null : headers,
      responseType: ResponseType.json,
    ));
  }

  Future<List<String>> getRoots() async {
    final dio = _dio();
    final resp = await dio.get('/api/roots');
    final data = resp.data;
    if (data is Map<String, dynamic> && data['roots'] is List) {
      return (data['roots'] as List).map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<List<GatewayEntry>> list({required String root, required String path}) async {
    final dio = _dio();
    final resp = await dio.get('/api/list', queryParameters: {
      'root': root,
      'path': path,
    });
    final data = resp.data;
    if (data is Map<String, dynamic> && data['entries'] is List) {
      return (data['entries'] as List)
          .map((e) => GatewayEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  /// Build a full media URL to download/stream a file.
  String buildMediaUrl(String root, String filePath) {
    final normalized = filePath.startsWith('/') ? filePath.substring(1) : filePath;
    final encodedSegments = normalized.split('/').map(Uri.encodeComponent).join('/');
    final b = _normalizedBase();
    final eroot = Uri.encodeComponent(root);
    return '$b/media/$eroot/$encodedSegments';
  }

  /// Download a media file to the app's documents directory.
  /// Returns the saved absolute file path.
  Future<String> downloadMediaToDocs({
    required String root,
    required String filePath,
    String? saveFileName,
    ProgressCallback? onReceiveProgress,
  }) async {
    final url = buildMediaUrl(root, filePath);
    // Save under Documents/MediaGateway/<root>/<filePath>
    final localPath = await resolveLocalPath(root: root, filePath: filePath, overrideFileName: saveFileName);
    await _downloadToPath(url: url, savePath: localPath, onReceiveProgress: onReceiveProgress);
    return localPath;
  }

  /// Download any absolute URL to documents dir, using configured auth headers if present.
  Future<String> downloadUrlToDocs(
    String url, {
    String? saveFileName,
    ProgressCallback? onReceiveProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = saveFileName ?? (Uri.parse(url).pathSegments.isNotEmpty ? Uri.parse(url).pathSegments.last : 'download.bin');
    final savePath = '${dir.path}/$name';
    await _downloadToPath(url: url, savePath: savePath, onReceiveProgress: onReceiveProgress);
    return savePath;
  }

  Future<void> _downloadToPath({
    required String url,
    required String savePath,
    ProgressCallback? onReceiveProgress,
  }) async {
    final dio = _dio(overrideBase: ''); // absolute URL, base not needed
    // Ensure parent directory exists
    final parent = File(savePath).parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await dio.download(
      url,
      savePath,
      onReceiveProgress: onReceiveProgress,
      options: Options(headers: _authHeaders()),
    );
  }

  /// Compute the local absolute path under Documents/MediaGateway/<root>/<filePath>.
  /// Optionally override only the final file name.
  Future<String> resolveLocalPath({
    required String root,
    required String filePath,
    String? overrideFileName,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final normalized = filePath.startsWith('/') ? filePath.substring(1) : filePath;
    final fileName = overrideFileName ?? (normalized.split('/').isNotEmpty ? normalized.split('/').last : 'download.bin');
    final subDir = normalized.split('/')..removeLast();
    final joinedSubDir = subDir.isEmpty ? '' : '/${subDir.join('/') }';
    return '${docs.path}/MediaGateway/$root$joinedSubDir/$fileName';
  }

  /// Check if a given remote file is already downloaded locally.
  Future<bool> existsLocally({required String root, required String filePath}) async {
    final p = await resolveLocalPath(root: root, filePath: filePath);
    return File(p).exists();
  }
}
