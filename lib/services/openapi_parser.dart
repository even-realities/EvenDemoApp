import 'dart:convert';

import 'package:yaml/yaml.dart' as y;

class SwaggerImportResult {
  final String? baseUrl;
  final String? firstPostPath;
  final String? textFieldName;

  SwaggerImportResult({this.baseUrl, this.firstPostPath, this.textFieldName});
}

class OpenApiParser {
  static SwaggerImportResult fromYaml(String yaml) {
    final doc = y.loadYaml(yaml);
    final servers = (doc['servers'] as List?) ?? const [];
    final serverUrl = servers.isNotEmpty ? servers.first['url'] as String? : null;

    final paths = doc['paths'] as Map?;
    String? firstPostPath;
    String? textField;
    if (paths != null) {
      for (final entry in paths.entries) {
        final methods = entry.value as Map?;
        if (methods != null && methods.containsKey('post')) {
          firstPostPath = entry.key as String;
          final post = methods['post'] as Map?;
          // Try to find a likely text field from requestBody schema
          final reqBody = post?['requestBody'] as Map?;
          final content = reqBody?['content'] as Map?;
          final appJson = content?['application/json'] as Map?;
          final schema = appJson?['schema'] as Map?;
          final props = schema?['properties'] as Map?;
          if (props != null) {
            // Heuristic: prefer fields named 'text', 'message', 'query'
            for (final key in ['text', 'message', 'query', 'input']) {
              if (props.containsKey(key)) {
                textField = key;
                break;
              }
            }
          }
          break;
        }
      }
    }

    return SwaggerImportResult(
      baseUrl: serverUrl,
      firstPostPath: firstPostPath,
      textFieldName: textField,
    );
  }

  static SwaggerImportResult fromJson(String jsonStr) {
    final doc = jsonDecode(jsonStr) as Map<String, dynamic>;
    final servers = (doc['servers'] as List?) ?? const [];
    final serverUrl = servers.isNotEmpty ? servers.first['url'] as String? : null;

    final paths = doc['paths'] as Map<String, dynamic>?;
    String? firstPostPath;
    String? textField;
    if (paths != null) {
      for (final entry in paths.entries) {
        final methods = entry.value as Map<String, dynamic>?;
        if (methods != null && methods.containsKey('post')) {
          firstPostPath = entry.key;
          final post = methods['post'] as Map<String, dynamic>?;
          final reqBody = post?['requestBody'] as Map<String, dynamic>?;
          final content = reqBody?['content'] as Map<String, dynamic>?;
          final appJson = content?['application/json'] as Map<String, dynamic>?;
          final schema = appJson?['schema'] as Map<String, dynamic>?;
          final props = schema?['properties'] as Map<String, dynamic>?;
          if (props != null) {
            for (final key in ['text', 'message', 'query', 'input']) {
              if (props.containsKey(key)) {
                textField = key;
                break;
              }
            }
          }
          break;
        }
      }
    }

    return SwaggerImportResult(
      baseUrl: serverUrl,
      firstPostPath: firstPostPath,
      textFieldName: textField,
    );
  }
}
