import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/equalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Metal+ matches the approved six-band curve and protects headroom', () {
    final preset = builtInPreset('metal_plus');
    expect(preset.name, 'Metal+');
    expect(preset.gains, [5.5, 2.5, -0.5, 0, 2, 3.5]);
    expect(preset.preampDb, -5.5);
  });

  test('preset payload accepts exactly six finite gains in range', () {
    final preset = EqualizerPreset.fromPayload({
      'id': 'custom-id',
      'name': 'Metal room',
      'gains': [12, -12, 0, 1.5, 2, 3],
    });
    expect(preset.gains.length, 6);
    expect(
      () => EqualizerPreset.fromPayload({
        'id': 'custom-id',
        'name': 'Broken',
        'gains': [0, 1],
      }),
      throwsFormatException,
    );
  });

  test(
    'remote preset update follows locally active preset, delete falls back',
    () {
      final controller = AppController();
      const id = '9c18e782-318c-4a69-b822-8dc70c3d54ce';
      controller.apply('equalizer.preset.upsert', {
        'id': id,
        'name': 'My metal',
        'gains': [1, 2, 3, 4, 5, 6],
      });
      controller.activeEqualizerPresetId = id;
      controller.apply('equalizer.preset.upsert', {
        'id': id,
        'name': 'My metal v2',
        'gains': [6, 5, 4, 3, 2, 1],
      });
      expect(controller.equalizerGains, [6, 5, 4, 3, 2, 1]);

      controller.apply('equalizer.preset.delete', {'id': id});
      expect(controller.activeEqualizerPresetId, 'flat');
      expect(controller.equalizerGains, List<double>.filled(6, 0));
      controller.dispose();
    },
  );

  test(
    'selecting a built-in preset is local and creates no sync operation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppController()..account = 'test-account';
      await controller.selectEqualizerPreset('metal_plus');
      expect(controller.activeEqualizerPresetId, 'metal_plus');
      expect(controller.pending, isEmpty);
      controller.dispose();
    },
  );
}
