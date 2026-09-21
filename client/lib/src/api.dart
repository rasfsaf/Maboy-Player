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

  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
      throw ApiException('Требуется HTTPS (кроме локального сервера)', 0);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final text = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException('${decoded['detail'] ?? 'Ошибка сервера'}', response.statusCode);
      }
      return decoded;
    } on SocketException {
      throw ApiException('Сервер недоступен; изменения останутся на устройстве', 0);
    } on TimeoutException {
      throw ApiException('Истекло время ожидания сервера', 0);
    } finally {
      client.close(force: true);
    }
  }
}