import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maboy/src/services/audio_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows mpv plays, seeks and applies live EQ', (tester) async {
    if (!Platform.isWindows) return;
    final fixture = await _writeToneFixture();
    final player = MaboyAudioPlayer();
    try {
      await player.setEqualizer(
        enabled: true,
        gains: const [5.5, 2.5, -0.5, 0, 2, 3.5],
      );
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'smoke-tone',
          uri: fixture.uri,
          title: 'Playback smoke tone',
          artist: 'maboy tests',
          album: 'real scenarios',
        ),
      );
      await player.play();
      await _waitUntil(
        () => player.position > const Duration(milliseconds: 150),
        const Duration(seconds: 8),
      );
      expect(player.playing, isTrue);

      await player.seek(const Duration(milliseconds: 700));
      await _waitUntil(
        () => player.position >= const Duration(milliseconds: 600),
        const Duration(seconds: 3),
      );
      await player.setEqualizer(enabled: true, gains: const [3, 5, 1, 3, 1, 2]);
      await player.pause();
      expect(player.playing, isFalse);
    } finally {
      await player.dispose();
      if (await fixture.exists()) await fixture.delete();
    }
  });
}

Future<void> _waitUntil(bool Function() condition, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Playback condition was not reached within $timeout',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<File> _writeToneFixture() async {
  const sampleRate = 44100;
  const seconds = 3;
  const channels = 1;
  const bitsPerSample = 16;
  final sampleCount = sampleRate * seconds;
  final dataSize = sampleCount * channels * (bitsPerSample ~/ 8);
  final bytes = ByteData(44 + dataSize);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var sample = 0; sample < sampleCount; sample++) {
    final envelope =
        math.min(1.0, sample / 300.0) *
        math.min(1.0, (sampleCount - sample) / 300.0);
    final value =
        (math.sin(2 * math.pi * 440 * sample / sampleRate) * 9000 * envelope)
            .round();
    bytes.setInt16(44 + sample * 2, value, Endian.little);
  }
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}maboy-playback-smoke.wav',
  );
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file;
}
