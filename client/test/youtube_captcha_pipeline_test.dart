import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/captcha_solver_service.dart';
import 'package:maboy/src/services/youtube_downloader.dart';

class _CountingSolver extends CaptchaClient {
  _CountingSolver(this.token);
  final String token;
  int calls = 0;

  @override
  String get name => 'fake';

  @override
  Future<String> solve(CaptchaTask task, {Duration timeout = const Duration(seconds: 180)}) async {
    calls += 1;
    return token;
  }
}

void main() {
  test('download pipeline skips the solver when youtube did not ask for captcha', () async {
    final solver = _CountingSolver('unused');
    final service = YouTubeDownloadService(captcha: CaptchaSolverService(clients: [solver]));
    final retry = await service.captchaRetryArgs('HTTP Error 403: Forbidden', ['-x', 'url']);
    expect(retry, isNull);
    expect(solver.calls, 0);
  });

  test('download pipeline asks the solver and retries with a po token when captcha is required', () async {
    final solver = _CountingSolver('captcha-ok');
    final service = YouTubeDownloadService(captcha: CaptchaSolverService(clients: [solver]));
    final retry = await service.captchaRetryArgs(
      'Sign in to confirm you’re not a bot',
      ['-x', 'https://www.youtube.com/watch?v=abc'],
    );
    expect(solver.calls, 1);
    expect(retry, isNotNull);
    expect(retry!.last, 'youtube:po_token=web.gvs+${base64Encode(utf8.encode('captcha-ok'))}');
  });
}
