import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/performance_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerformanceService', () {
    test('Default mode is auto', () {
      final service = PerformanceService.custom(isLowEndDeviceOverride: false);
      expect(service.mode, PerformanceMode.auto);
      expect(service.isOptimized, isFalse);
      expect(service.enableBackdropBlur, isTrue);
      expect(service.glassBlurSigma, 10.0);
    });

    test('Auto mode on low-end device activates optimizations', () {
      final service = PerformanceService.custom(
        isLowEndDeviceOverride: true,
        ramMbOverride: 1894,
        cpuCoresOverride: 4,
      );
      expect(service.mode, PerformanceMode.auto);
      expect(service.isOptimized, isTrue);
      expect(service.enableBackdropBlur, isFalse);
      expect(service.glassBlurSigma, 0.0);
      expect(service.backgroundBlurSigma, 6.0);
      expect(service.enableContinuousAnimations, isFalse);
      expect(service.deviceSummary, contains('Слабое устройство'));
      expect(service.deviceSummary, contains('1894 МБ ОЗУ'));
    });

    test('highPerformance mode forces optimizations regardless of device', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = PerformanceService.custom(
        isLowEndDeviceOverride: false,
        prefs: prefs,
      );
      await service.setMode(PerformanceMode.highPerformance);

      expect(service.isOptimized, isTrue);
      expect(service.enableBackdropBlur, isFalse);
      expect(service.glassBlurSigma, 0.0);
      expect(service.enableContinuousAnimations, isFalse);
      expect(prefs.getString(PerformanceService.prefKeyMode), 'highPerformance');
    });

    test('highQuality mode disables optimizations on low-end device', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = PerformanceService.custom(
        isLowEndDeviceOverride: true,
        prefs: prefs,
      );
      await service.setMode(PerformanceMode.highQuality);

      expect(service.isOptimized, isFalse);
      expect(service.enableBackdropBlur, isTrue);
      expect(service.glassBlurSigma, 10.0);
      expect(service.enableContinuousAnimations, isTrue);
    });

    test('Restores saved mode from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        PerformanceService.prefKeyMode: 'highPerformance',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = PerformanceService.custom(prefs: prefs);
      await service.init(prefs: prefs);

      expect(service.mode, PerformanceMode.highPerformance);
      expect(service.isOptimized, isTrue);
    });

    test('AMOLED mode defaults to isOptimized and can be explicitly overridden', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final lowEndService = PerformanceService.custom(
        isLowEndDeviceOverride: true,
        prefs: prefs,
      );
      expect(lowEndService.enableAmoledBlack, isTrue);

      final highEndService = PerformanceService.custom(
        isLowEndDeviceOverride: false,
        prefs: prefs,
      );
      expect(highEndService.enableAmoledBlack, isFalse);

      await highEndService.setAmoledBlack(true);
      expect(highEndService.enableAmoledBlack, isTrue);
      expect(prefs.getBool(PerformanceService.prefKeyAmoled), isTrue);

      await lowEndService.setAmoledBlack(false);
      expect(lowEndService.enableAmoledBlack, isFalse);
      expect(prefs.getBool(PerformanceService.prefKeyAmoled), isFalse);
    });

    test('Battery saver defaults to true and can be toggled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final service = PerformanceService.custom(prefs: prefs);
      expect(service.batterySaver, isTrue);

      await service.setBatterySaver(false);
      expect(service.batterySaver, isFalse);
      expect(prefs.getBool(PerformanceService.prefKeyBatterySaver), isFalse);

      await service.setBatterySaver(true);
      expect(service.batterySaver, isTrue);
      expect(prefs.getBool(PerformanceService.prefKeyBatterySaver), isTrue);
    });

    test('Restores AMOLED and battery saver settings from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        PerformanceService.prefKeyMode: 'highPerformance',
        PerformanceService.prefKeyAmoled: true,
        PerformanceService.prefKeyBatterySaver: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = PerformanceService.custom();
      await service.init(prefs: prefs);

      expect(service.mode, PerformanceMode.highPerformance);
      expect(service.enableAmoledBlack, isTrue);
      expect(service.batterySaver, isFalse);
    });
  });
}
