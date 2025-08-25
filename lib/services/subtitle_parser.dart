class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleCue({required this.start, required this.end, required this.text});
}

class SubtitleParser {
  static List<SubtitleCue> parse(String content, {String? extension}) {
    final lowerExt = (extension ?? '').toLowerCase();
    if (lowerExt.endsWith('.vtt')) {
      final v = _parseWebVtt(content);
      if (v.isNotEmpty) return v;
      // fallback to srt if malformed
      return _parseSrt(content);
    }
    if (lowerExt.endsWith('.srt')) {
      return _parseSrt(content);
    }
    // Try VTT first, then SRT
    final vtt = _parseWebVtt(content);
    if (vtt.isNotEmpty) return vtt;
    return _parseSrt(content);
  }

  static List<SubtitleCue> _parseSrt(String content) {
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final cues = <SubtitleCue>[];
    int i = 0;
    while (i < lines.length) {
      // skip index line
      if (lines[i].trim().isEmpty) {
        i++; continue;
      }
      // optional index
      final idxLine = lines[i].trim();
      if (RegExp(r'^\d+$').hasMatch(idxLine)) {
        i++;
      }
      if (i >= lines.length) break;
      final timeLine = lines[i].trim();
      final m = RegExp(r'(?<s>\d{1,2}:\d{2}:\d{2},\d{1,3})\s*-->\s*(?<e>\d{1,2}:\d{2}:\d{2},\d{1,3})').firstMatch(timeLine);
      if (m == null) { i++; continue; }
      i++;
      final buf = StringBuffer();
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        buf.writeln(lines[i]);
        i++;
      }
      final text = buf.toString().trim();
      final start = _parseSrtTimestamp(m.namedGroup('s')!);
      final end = _parseSrtTimestamp(m.namedGroup('e')!);
      cues.add(SubtitleCue(start: start, end: end, text: text));
      // skip empty line
      while (i < lines.length && lines[i].trim().isEmpty) i++;
    }
    return cues;
  }

  static List<SubtitleCue> _parseWebVtt(String content) {
    final text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n');
    int i = 0;
    // optional WEBVTT header
    if (i < lines.length && lines[i].trim().toUpperCase().startsWith('WEBVTT')) {
      // skip header and possible note lines until blank
      while (i < lines.length && lines[i].trim().isNotEmpty) i++;
      while (i < lines.length && lines[i].trim().isEmpty) i++;
    }
    final cues = <SubtitleCue>[];
    while (i < lines.length) {
      // skip optional identifier
      if (i < lines.length && lines[i].trim().isNotEmpty && !lines[i].contains('-->')) {
        i++;
      }
      if (i >= lines.length) break;
      final timeLine = lines[i].trim();
      final m = RegExp(r'(?<s>\d{1,2}:\d{2}(:\d{2})?(\.\d{1,3})?)\s*-->\s*(?<e>\d{1,2}:\d{2}(:\d{2})?(\.\d{1,3})?)').firstMatch(timeLine);
      if (m == null) { i++; continue; }
      i++;
      final buf = StringBuffer();
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        buf.writeln(lines[i]);
        i++;
      }
      final text = buf.toString().trim();
      final start = _parseVttTimestamp(m.namedGroup('s')!);
      final end = _parseVttTimestamp(m.namedGroup('e')!);
      cues.add(SubtitleCue(start: start, end: end, text: text));
      while (i < lines.length && lines[i].trim().isEmpty) i++;
    }
    return cues;
  }

  static Duration _parseSrtTimestamp(String s) {
    final parts = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2}),(\d{1,3})$').firstMatch(s)!;
    final h = int.parse(parts.group(1)!);
    final m = int.parse(parts.group(2)!);
    final sec = int.parse(parts.group(3)!);
    final ms = int.parse(parts.group(4)!.padRight(3, '0'));
    return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
    }

  static Duration _parseVttTimestamp(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.(\d{1,3}))?$').firstMatch(s)!;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final sec = int.parse(m.group(3) ?? '0');
    final ms = int.parse((m.group(4) ?? '0').padRight(3, '0'));
    return Duration(hours: h, minutes: min, seconds: sec, milliseconds: ms);
  }
}
