import 'dart:typed_data';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';

class SilentAudioKeeper {
  SilentAudioKeeper._();
  static final SilentAudioKeeper instance = SilentAudioKeeper._();

  final AudioPlayer _player = AudioPlayer();
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start({int sampleRate = 16000, int seconds = 1}) async {
    if (_running) return;
    // Loop a short silent WAV
    final bytes = _generateSilentWav(sampleRate: sampleRate, seconds: seconds);
    await _player.setReleaseMode(ReleaseMode.loop);
    // Keep the session in playback and mix with others
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    await _player.play(BytesSource(bytes, mimeType: 'audio/wav'), volume: 0.0);
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _player.stop();
    _running = false;
  }

  // PCM16 mono WAV header + zeros
  Uint8List _generateSilentWav({required int sampleRate, required int seconds}) {
    final numSamples = sampleRate * seconds;
    final headerSize = 44;
    final dataSize = numSamples * 2; // 16-bit mono
    final totalSize = headerSize + dataSize;
    final bytes = Uint8List(totalSize);
    final bd = ByteData.view(bytes.buffer);

    // RIFF header
    _writeString(bytes, 0, 'RIFF');
    bd.setUint32(4, totalSize - 8, Endian.little);
    _writeString(bytes, 8, 'WAVE');

    // fmt chunk
    _writeString(bytes, 12, 'fmt ');
    bd.setUint32(16, 16, Endian.little); // PCM chunk size
    bd.setUint16(20, 1, Endian.little); // PCM format
    bd.setUint16(22, 1, Endian.little); // channels: 1
    bd.setUint32(24, sampleRate, Endian.little);
    final byteRate = sampleRate * 2; // sr * channels * bits/8
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, 2, Endian.little); // block align
    bd.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    _writeString(bytes, 36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    // data is already zero (silence)
    return bytes;
  }

  void _writeString(Uint8List b, int offset, String s) {
    final codes = s.codeUnits;
    for (var i = 0; i < codes.length; i++) {
      b[offset + i] = codes[i];
    }
  }
}
