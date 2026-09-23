import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/api.dart';

void main() {
  test(
    'server download keeps a complete file published by another source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'maboy-download-test-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final target = File('${directory.path}/track.mp3');
      final existingAudio = List<int>.filled(6_001, 1);
      final serverAudio = List<int>.filled(6_002, 2);
      final responseStarted = Completer<void>();
      final publishAudio = Completer<void>();
      final subscription = server.listen((request) async {
        request.response.add(serverAudio.sublist(0, 3_000));
        await request.response.flush();
        responseStarted.complete();
        await publishAudio.future;
        request.response.add(serverAudio.sublist(3_000));
        await request.response.close();
      });

      try {
        final api = SyncApi('http://127.0.0.1:${server.port}', null);
        final download = api.downloadFile('/audio', target.path);
        await responseStarted.future;
        await target.writeAsBytes(existingAudio);
        publishAudio.complete();
        final result = await download;

        expect(result.path, target.path);
        expect(await target.readAsBytes(), existingAudio);
        expect(await File('${target.path}.server.part').exists(), isFalse);
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
