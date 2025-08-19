import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ElevenLabsConfig {
  final String apiKey;
  final String modelId;
  final String voiceId;
  final double stability;
  final double similarityBoost;
  final String outputFormat; // e.g., mp3_44100_128

  const ElevenLabsConfig({
    required this.apiKey,
    required this.modelId,
    required this.voiceId,
    required this.stability,
    required this.similarityBoost,
    required this.outputFormat,
  });

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'modelId': modelId,
        'voiceId': voiceId,
        'stability': stability,
        'similarityBoost': similarityBoost,
        'outputFormat': outputFormat,
      };

  factory ElevenLabsConfig.fromJson(Map<String, dynamic> json) => ElevenLabsConfig(
        apiKey: json['apiKey'] as String? ?? '',
        modelId: json['modelId'] as String? ?? 'eleven_v3',
        voiceId: json['voiceId'] as String? ?? 'bqpOyYNUu11tjjvRUbKn',
        stability: (json['stability'] as num?)?.toDouble() ?? 0.5,
        similarityBoost: (json['similarityBoost'] as num?)?.toDouble() ?? 0.5,
        outputFormat: json['outputFormat'] as String? ?? 'mp3_44100_128',
      );
}

class ElevenLabsService {
  static const _prefsKey = 'elevenlabs_config_v1';
  final Dio _dio;
  ElevenLabsService([Dio? dio]) : _dio = dio ?? Dio();

  Future<ElevenLabsConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const ElevenLabsConfig(
        apiKey: '',
        modelId: 'eleven_v3',
        voiceId: 'bqpOyYNUu11tjjvRUbKn', // Yamato (example)
        stability: 0.5,
        similarityBoost: 0.5,
        outputFormat: 'mp3_44100_128',
      );
    }
    return ElevenLabsConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveConfig(ElevenLabsConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<Response<Uint8List>> synthesize({
    required ElevenLabsConfig config,
    required String text,
  }) async {
    final url = 'https://api.elevenlabs.io/v1/text-to-speech/${config.voiceId}';
    final headers = {
      'Accept': 'audio/mpeg',
      'Content-Type': 'application/json',
      'xi-api-key': config.apiKey,
    };
    final body = {
      'text': text,
      'model_id': config.modelId,
      'voice_settings': {
        'stability': config.stability,
        'similarity_boost': config.similarityBoost,
      },
      'output_format': config.outputFormat,
    };

    try {
      return await _dio.post(
        url,
        data: jsonEncode(body),
        options: Options(headers: headers, responseType: ResponseType.bytes),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final respHeaders = e.response?.headers.map;
      String bodyStr = '';
      final data = e.response?.data;
      if (data is Uint8List) {
        bodyStr = utf8.decode(data, allowMalformed: true);
      } else if (data is String) {
        bodyStr = data;
      } else if (data != null) {
        bodyStr = data.toString();
      }
      // Debug log to terminal
      // ignore: avoid_print
      print('[ElevenLabs] HTTP $status\nHeaders: $respHeaders\nBody: $bodyStr');
      rethrow;
    }
  }

  // --- Metadata ---
  Future<List<ElevenVoice>> listVoices(String apiKey) async {
    final resp = await _dio.get(
      'https://api.elevenlabs.io/v1/voices',
      options: Options(headers: {'xi-api-key': apiKey}),
    );
    final voices = <ElevenVoice>[];
    final data = resp.data;
    if (data is Map && data['voices'] is List) {
      for (final v in (data['voices'] as List)) {
        if (v is Map) {
          voices.add(ElevenVoice(
            id: (v['voice_id'] ?? v['voiceId'] ?? '').toString(),
            name: (v['name'] ?? '').toString(),
          ));
        }
      }
    }
    return voices;
  }

  Future<List<ElevenModel>> listModels(String apiKey) async {
    try {
      final resp = await _dio.get(
        'https://api.elevenlabs.io/v1/models',
        options: Options(headers: {'xi-api-key': apiKey}),
      );
      final models = <ElevenModel>[];
      final data = resp.data;
      if (data is List) {
        for (final m in data) {
          if (m is Map) {
            final id = (m['model_id'] ?? m['modelId'] ?? '').toString();
            final name = (m['name'] ?? id).toString();
            if (id.isNotEmpty) models.add(ElevenModel(id: id, name: name));
          }
        }
      }
      return models;
    } catch (_) {
      // Fallback to common options if listing fails
      return [
        ElevenModel(id: 'eleven_multilingual_v2', name: 'eleven_multilingual_v2 (recommended)'),
        ElevenModel(id: 'eleven_v3', name: 'eleven_v3'),
        ElevenModel(id: 'eleven_flash_v2_5', name: 'eleven_flash_v2_5'),
        ElevenModel(id: 'eleven_turbo_v2_5', name: 'eleven_turbo_v2_5'),
      ];
    }
  }
}

class ElevenVoice {
  final String id;
  final String name;
  ElevenVoice({required this.id, required this.name});
}

class ElevenModel {
  final String id;
  final String name;
  ElevenModel({required this.id, required this.name});
}
