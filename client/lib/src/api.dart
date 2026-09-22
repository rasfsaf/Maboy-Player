import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      throw ApiException('Сервер недоступен (${e.message})', 0);
    } on TimeoutException {
      throw ApiException('Истекло время ожидания ответа сервера', 0);
    } finally {
      client.close(force: true);
    }
  }
}
