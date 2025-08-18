import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ReaderAction {
  nextPage,
  previousPage,
  autoScrollStart,
  autoScrollStop,
}

class InputMappingService {
  static const _prefsKey = 'input_mapping_v1';
  static final InputMappingService instance = InputMappingService._();
  InputMappingService._();

  // action -> set of control ids
  Map<ReaderAction, Set<String>> _mapping = _defaultMapping();

  static Map<ReaderAction, Set<String>> _defaultMapping() => {
        ReaderAction.nextPage: {
          'dpadRight', 'buttonA', 'rightShoulder', 'rightTrigger', 'nextTrack'
        },
        ReaderAction.previousPage: {
          'dpadLeft', 'buttonB', 'leftShoulder', 'leftTrigger', 'previousTrack'
        },
        ReaderAction.autoScrollStart: {
          'buttonX', 'dpadUp', 'play', 'togglePlayPause'
        },
        ReaderAction.autoScrollStop: {
          'buttonY', 'dpadDown', 'pause', 'pauseButton'
        },
      };

  Map<ReaderAction, Set<String>> get mapping => _mapping;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <ReaderAction, Set<String>>{};
    for (final entry in decoded.entries) {
      final action = ReaderAction.values.firstWhere(
        (a) => a.toString() == entry.key,
        orElse: () => ReaderAction.nextPage,
      );
      final list = (entry.value as List).map((e) => e.toString()).toSet();
      result[action] = list;
    }
    _mapping = result;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final enc = <String, List<String>>{};
    for (final entry in _mapping.entries) {
      enc[entry.key.toString()] = entry.value.toList();
    }
    await prefs.setString(_prefsKey, jsonEncode(enc));
  }

  void setControls(ReaderAction action, Set<String> controls) {
    _mapping[action] = controls;
  }

  ReaderAction? actionForControl(String control) {
    for (final entry in _mapping.entries) {
      if (entry.value.contains(control)) return entry.key;
    }
    return null;
  }

  static List<String> allControls = [
    // Gamepad
    'dpadUp', 'dpadDown', 'dpadLeft', 'dpadRight',
    'buttonA', 'buttonB', 'buttonX', 'buttonY',
    'leftShoulder', 'rightShoulder', 'leftTrigger', 'rightTrigger',
    'pauseButton',
    // Remote (audio)
    'play', 'pause', 'togglePlayPause', 'nextTrack', 'previousTrack',
  ];
}
