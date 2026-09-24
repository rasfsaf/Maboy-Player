import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/captcha_solver_service.dart';
import 'package:maboy/src/services/p2p_sync_service.dart';

void main() {
  test('p2p prefers youtube without a local file when a peer is online', () {
    const sync = P2pSyncService();
    expect(
      sync.preferPeerForYouTube(hasOnlinePeers: true, provider: 'youtube', hasLocalFile: false),
      isTrue,
    );
    expect(
      sync.preferPeerForYouTube(hasOnlinePeers: false, provider: 'youtube', hasLocalFile: false),
      isFalse,
    );
  });

  test('handshake retry does not record a permanent download failure', () {
    const sync = P2pSyncService();
    expect(sync.shouldRecordFailedDownload(handshakeRetry: true), isFalse);
    final cleared = sync.failedDownloadsAfterPeerOnline({'a': 'err'}, true);
    expect(cleared, isEmpty);
  });

  test('captcha chain returns null when no provider is configured', () async {
    final solver = CaptchaSolverService(clients: const []);
    final token = await solver.solve(
      const CaptchaTask(type: 'RecaptchaV2TaskProxyless', websiteUrl: 'https://www.youtube.com', websiteKey: 'k'),
    );
    expect(token, isNull);
  });
}
