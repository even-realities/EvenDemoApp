import 'dart:async';

import 'package:flutter/services.dart';

class ControllerEvents {
  static const _eventChannelName = 'eventController';
  static final ControllerEvents _instance = ControllerEvents._internal();
  factory ControllerEvents() => _instance;
  ControllerEvents._internal();

  final EventChannel _channel = const EventChannel(_eventChannelName);
  Stream<Map<String, dynamic>>? _stream;

  Stream<Map<String, dynamic>> get stream {
    _stream ??= _channel
        .receiveBroadcastStream(_eventChannelName)
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _stream!;
  }
}
