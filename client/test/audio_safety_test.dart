import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio Safety & Becoming Noisy Protection', () {
    test('pauseDueToBecomingNoisy halts playback and sets unsolicitedPlayBlocked', () async {
      final player = MaboyAudioPlayer();

      expect(player.playing, isFalse);
      expect(player.unsolicitedPlayBlocked, isFalse);

      await player.pauseDueToBecomingNoisy();

      expect(player.playing, isFalse);
      expect(player.unsolicitedPlayBlocked, isTrue);

      player.clearUnsolicitedPlayBlock();
      expect(player.unsolicitedPlayBlocked, isFalse);

      await player.dispose();
    });

    test('explicit clearUnsolicitedPlayBlock resets the block latch', () async {
      final player = MaboyAudioPlayer();

      await player.pauseDueToBecomingNoisy();
      expect(player.unsolicitedPlayBlocked, isTrue);

      player.clearUnsolicitedPlayBlock();
      expect(player.unsolicitedPlayBlocked, isFalse);

      await player.dispose();
    });
  });
}
