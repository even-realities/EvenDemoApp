import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  final String baseUrl;
  final String path;
  final Map<String, String> headers;
  final Map<String, String> query;
  final String textFieldName;

  const ApiConfig({
    required this.baseUrl,
    required this.path,
    required this.headers,
    required this.query,
    required this.textFieldName,
  });

  Uri buildUri() => Uri.parse(baseUrl).resolve(path).replace(queryParameters: {
        ...query,
      });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'path': path,
        'headers': headers,
        'query': query,
        'textFieldName': textFieldName,
      };

  factory ApiConfig.fromJson(Map<String, dynamic> json) => ApiConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        path: json['path'] as String? ?? '/',
        headers: (json['headers'] as Map?)?.cast<String, String>() ?? const {},
        query: (json['query'] as Map?)?.cast<String, String>() ?? const {},
        textFieldName: json['textFieldName'] as String? ?? 'text',
      );
}

class ApiClient {
  static const _prefsKey = 'api_config_v1';
  final Dio _dio;

  ApiClient([Dio? dio]) : _dio = dio ?? Dio();

  Future<ApiConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const ApiConfig(
        baseUrl: 'https://example.com',
        path: '/api/endpoint',
        headers: {},
        query: {},
        textFieldName: 'text',
      );
    }
    return ApiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveConfig(ApiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<Response<dynamic>> postText({
    required ApiConfig config,
    required String text,
  }) async {
    final uri = config.buildUri();
    final headers = Map<String, dynamic>.from(config.headers);

    final data = {config.textFieldName: text};

    return _dio.postUri(uri, data: data, options: Options(headers: headers));
  }
}
