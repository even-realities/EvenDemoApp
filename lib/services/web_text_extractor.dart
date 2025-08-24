import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class WebTextExtractorResult {
  final String url;
  final String? title;
  final List<String> textBlocks; // paragraphs, list items
  final List<String> codeBlocks; // code/pre blocks
  final String? rawTextFallback;
  WebTextExtractorResult({
    required this.url,
    this.title,
    required this.textBlocks,
    required this.codeBlocks,
    this.rawTextFallback,
  });
}

class WebTextExtractor {
  final Dio _dio;
  WebTextExtractor([Dio? dio]) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 12)));

  Future<WebTextExtractorResult> fetchAndExtract(String url) async {
    final resp = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
    final body = resp.data ?? '';

    // Parse HTML
    final doc = html_parser.parse(body);
    final title = doc.querySelector('title')?.text.trim();

    // Prefer semantic containers
    dom.Element? root = doc.querySelector('main, article, #content, .content, #article, .article');
    root ??= doc.body;

    final textBlocks = <String>[];
    final codeBlocks = <String>[];

    if (root != null) {
      // Extract code first to keep separated
      for (final pre in root.querySelectorAll('pre, code')) {
        final codeText = _nodeText(pre).trim();
        if (codeText.isNotEmpty) codeBlocks.add(codeText);
        pre.remove(); // avoid duplication in text
      }

      // Headings and paragraphs
      for (final el in root.querySelectorAll('h1, h2, h3, p, li')) {
        final t = _nodeText(el).trim();
        if (t.isNotEmpty) textBlocks.add(t);
      }
    }

    // Fallback if empty
    String? fallback;
    if (textBlocks.isEmpty && codeBlocks.isEmpty) {
      fallback = _nodeText(doc.body).trim();
    }

    return WebTextExtractorResult(
      url: url,
      title: title,
      textBlocks: textBlocks,
      codeBlocks: codeBlocks,
      rawTextFallback: fallback,
    );
  }

  String _nodeText(dom.Node? n) {
    if (n == null) return '';
    return n.text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  }
}
