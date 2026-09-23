import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Преобразует низкоуровневые сетевые сбои в понятное пользователю сообщение.
String formatNetworkError(Object error) {
  if (error is SocketException) {
    final msg = error.message.toLowerCase();
    final osMsg = error.osError?.message.toLowerCase() ?? '';
    if (msg.contains('refused') || osMsg.contains('refused')) {
      return 'Сервер временно недоступен';
    }
    return 'Вы не в сети';
  }
  if (error is TimeoutException) {
    return 'Вы не в сети';
  }
  if (error is HandshakeException) {
    return 'Ошибка защищённого соединения';
  }
  if (error is HttpException) {
    return 'Ошибка сетевого соединения';
  }
  return 'Вы не в сети';
}

/// Приводит любую ошибку к дружественному виду без технических дампов и адресов.
String friendlyErrorMessage(dynamic error) {
  if (error == null) return '';
  if (error is ApiException) {
    return error.message;
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is HttpException) {
    return formatNetworkError(error);
  }
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('no address associated') ||
      lower.contains('network error') ||
      lower.contains('connection closed') ||
      lower.contains('connection abort') ||
      lower.contains('connection reset') ||
      lower.contains('errno = 101') ||
      lower.contains('errno = 110') ||
      lower.contains('errno = 111') ||
      lower.contains('winerror 10060') ||
      lower.contains('winerror 10061') ||
      lower.contains('winerror 10054') ||
      lower.contains('winerror 10051')) {
    if (lower.contains('connection refused') || lower.contains('winerror 10061')) {
      return 'Сервер временно недоступен';
    }
    return 'Вы не в сети';
  }
  if (lower.contains('handshakeexception')) {
    return 'Ошибка защищённого соединения';
  }
  return text;
}

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SyncApi {
  SyncApi(this.baseUrl, this.token);
  final String baseUrl;
  final String? token;

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$baseUrl$path');
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
      throw ApiException('Требуется HTTPS (кроме локального сервера)', 0);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      final text = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        final detail = decoded['detail'];
        String msg;
        if (response.statusCode == 401) {
          msg = 'Неверный email или пароль';
        } else if (response.statusCode == 409 && path.contains('register')) {
          msg = 'Пользователь с таким email уже существует';
        } else if (detail != null) {
          msg = '$detail';
        } else {
          msg = 'Ошибка сервера (${response.statusCode})';
        }
        throw ApiException(msg, response.statusCode);
      }
      return decoded;
    } on SocketException catch (e) {
      throw ApiException(formatNetworkError(e), 0);
    } on TimeoutException catch (e) {
      throw ApiException(formatNetworkError(e), 0);
    } on HandshakeException catch (e) {
      throw ApiException(formatNetworkError(e), 0);
    } on HttpException catch (e) {
      throw ApiException(formatNetworkError(e), 0);
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadFile(
    String path,
    String outputFilePath, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
      throw ApiException('Требуется HTTPS (кроме локального сервера)', 0);
    }

    final target = File(outputFilePath);
    final temporary = File('$outputFilePath.server.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    IOSink? output;
    try {
      final request = await client.getUrl(uri);
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      // A cold server-side YouTube request includes download and ffmpeg
      // conversion before response headers are available. Connection setup is
      // still capped above; only authenticated media preparation may take
      // several minutes.
      final response = await request.close().timeout(
        const Duration(minutes: 5),
      );
      if (response.statusCode >= 400) {
        final text = await utf8.decoder.bind(response).join();
        String message = 'Ошибка сервера (${response.statusCode})';
        try {
          final decoded = jsonDecode(text) as Map<String, dynamic>;
          message = decoded['detail']?.toString() ?? message;
        } catch (_) {}
        throw ApiException(message, response.statusCode);
      }

      await temporary.parent.create(recursive: true);
      output = temporary.openWrite();
      var received = 0;
      final total = response.contentLength;
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        output.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(received / total);
        }
      }
      await output.flush();
      await output.close();
      output = null;
      if (received <= 5_000) {
        throw ApiException('Сервер вернул пустой аудиофайл', 502);
      }
      // A peer transfer may have finished while the server response was
      // streaming. Keep its complete file instead of deleting it.
      if (await _hasCompleteAudio(target)) return target;
      try {
        if (await target.exists()) await target.delete();
      } on FileSystemException {
        // Another writer can remove the stale target after exists().
        if (await target.exists()) rethrow;
      }
      try {
        return await temporary.rename(target.path);
      } on FileSystemException {
        // Another writer can publish a complete file before rename().
        if (await _hasCompleteAudio(target)) return target;
        rethrow;
      }
    } on SocketException catch (error) {
      throw ApiException(formatNetworkError(error), 0);
    } on TimeoutException catch (error) {
      throw ApiException(formatNetworkError(error), 0);
    } on HandshakeException catch (error) {
      throw ApiException(formatNetworkError(error), 0);
    } on HttpException catch (error) {
      throw ApiException(formatNetworkError(error), 0);
    } finally {
      await output?.close();
      if (await temporary.exists()) await temporary.delete();
      client.close(force: true);
    }
  }

  Future<bool> _hasCompleteAudio(File file) async {
    try {
      return await file.length() > 5_000;
    } on FileSystemException {
      return false;
    }
  }
}
