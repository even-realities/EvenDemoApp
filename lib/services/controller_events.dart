import 'dart:async';

import 'package:flutter/services.dart';

class ControllerEvents {
  static const _eventChannelName = 'eventController';
  static const _remoteChannelName = 'eventRemote';
  static final ControllerEvents _instance = ControllerEvents._internal();
  factory ControllerEvents() => _instance;
  ControllerEvents._internal();

  final EventChannel _channel = const EventChannel(_eventChannelName);
  final EventChannel _remote = const EventChannel(_remoteChannelName);
  Stream<Map<String, dynamic>>? _stream;
  Stream<Map<String, dynamic>>? _remoteStream;

  Stream<Map<String, dynamic>> get stream {
    _stream ??= _channel
        .receiveBroadcastStream(_eventChannelName)
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _stream!;
  }

  Stream<Map<String, dynamic>> get remoteStream {
    _remoteStream ??= _remote
        .receiveBroadcastStream(_remoteChannelName)
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _remoteStream!;
  }
}
