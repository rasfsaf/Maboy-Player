import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/api.dart';

void main() {
  group('Network error formatting', () {
    test('SocketException with connection timed out produces "Вы не в сети"', () {
      final error = const SocketException(
        'HTTP connection timed out after 0:00:25.000000, host: maboy.dofic.site, port: 443',
      );
      expect(formatNetworkError(error), 'Вы не в сети');
      expect(friendlyErrorMessage(error), 'Вы не в сети');
    });

    test('SocketException with Failed host lookup produces "Вы не в сети"', () {
      final error = const SocketException(
        "Failed host lookup: 'maboy.dofic.site'",
      );
      expect(formatNetworkError(error), 'Вы не в сети');
      expect(friendlyErrorMessage(error), 'Вы не в сети');
    });

    test('SocketException with Network unreachable produces "Вы не в сети"', () {
      final error = const SocketException(
        'OS Error: Network is unreachable, errno = 101',
      );
      expect(formatNetworkError(error), 'Вы не в сети');
      expect(friendlyErrorMessage(error), 'Вы не в сети');
    });

    test('SocketException with Connection refused produces "Сервер временно недоступен"', () {
      final error = const SocketException('Connection refused');
      expect(formatNetworkError(error), 'Сервер временно недоступен');
      expect(friendlyErrorMessage(error), 'Сервер временно недоступен');
    });

    test('TimeoutException produces "Вы не в сети"', () {
      final error = TimeoutException('Operation timed out');
      expect(formatNetworkError(error), 'Вы не в сети');
      expect(friendlyErrorMessage(error), 'Вы не в сети');
    });

    test('HandshakeException produces "Ошибка защищённого соединения"', () {
      const error = HandshakeException('Handshake error in client');
      expect(formatNetworkError(error), 'Ошибка защищённого соединения');
      expect(friendlyErrorMessage(error), 'Ошибка защищённого соединения');
    });

    test('ApiException preserves custom message', () {
      final error = ApiException('Неверный email или пароль', 401);
      expect(friendlyErrorMessage(error), 'Неверный email или пароль');
    });

    test('Raw error string matching user screenshot is converted to "Вы не в сети"', () {
      const rawString =
          'Сервер недоступен (HTTP connection timed out after 0:00:25.000000, host: maboy.dofic.site, port: 443)';
      expect(friendlyErrorMessage(rawString), 'Вы не в сети');
    });

    test('FormatException with Internal Server Error is converted to "Ошибка сервера (500)"', () {
      const error = FormatException('Unexpected character (at character 1)\nInternal Server Error\n^');
      expect(friendlyErrorMessage(error), 'Ошибка сервера (500)');
    });

    test('Generic FormatException is converted to "Некорректный ответ сервера"', () {
      const error = FormatException('Invalid JSON');
      expect(friendlyErrorMessage(error), 'Некорректный ответ сервера');
    });
  });
}
