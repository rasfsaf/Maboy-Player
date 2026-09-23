import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.documents);

  final String documents;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('maboy-local-restore-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(root.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test('deleting a discovered file preserves it and restore uses it', () async {
    final source = File('${root.path}${Platform.pathSeparator}source.mp3');
    await source.writeAsBytes([1, 2, 3]);
    final controller = AppController()..account = 'restore-discovered';
    controller.apply('track.upsert', {
      'id': 'discovered',
      'provider': 'local',
      'title': 'Song',
    });
    controller.localFiles['discovered'] = source.path;
    controller.originalFiles['discovered'] = source.path;

    await controller.deleteLocally(['discovered']);
    expect(await source.exists(), isTrue);
    expect(controller.localFiles.containsKey('discovered'), isFalse);
    expect(controller.deletedLocallyIds, contains('discovered'));

    await controller.restoreLocally('discovered');
    expect(controller.localFiles['discovered'], source.path);
    expect(controller.deletedLocallyIds, isNot(contains('discovered')));
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(
        prefs.getString('original_files_restore-discovered')!,
      )['discovered'],
      source.path,
    );
    controller.dispose();
  });

  test('deleting an imported copy restores from the source file', () async {
    final source = File('${root.path}${Platform.pathSeparator}source.mp3');
    await source.writeAsBytes([1, 2, 3]);
    final music = Directory('${root.path}${Platform.pathSeparator}music');
    await music.create();
    final copy = File('${music.path}${Platform.pathSeparator}imported.mp3');
    await source.copy(copy.path);
    final controller = AppController()..account = 'restore-imported';
    controller.apply('track.upsert', {
      'id': 'imported',
      'provider': 'local',
      'title': 'Song',
    });
    controller.localFiles['imported'] = copy.path;
    controller.originalFiles['imported'] = source.path;

    await controller.deleteLocally(['imported']);
    expect(await copy.exists(), isFalse);
    expect(await source.exists(), isTrue);

    await controller.restoreLocally('imported');
    expect(controller.localFiles['imported'], source.path);
    controller.dispose();
  });

  test('legacy discovered files gain a source marker on delete', () async {
    final source = File('${root.path}${Platform.pathSeparator}legacy.mp3');
    await source.writeAsBytes([1, 2, 3]);
    final controller = AppController()..account = 'restore-legacy';
    controller.apply('track.upsert', {
      'id': 'legacy',
      'provider': 'local',
      'title': 'Song',
    });
    controller.localFiles['legacy'] = source.path;

    await controller.deleteLocally(['legacy']);
    expect(await source.exists(), isTrue);
    expect(controller.originalFiles['legacy'], source.path);

    await controller.restoreLocally('legacy');
    expect(controller.localFiles['legacy'], source.path);
    controller.dispose();
  });
}
