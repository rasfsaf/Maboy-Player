import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CaptchaSolveException implements Exception {
  CaptchaSolveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CaptchaTask {
  const CaptchaTask({required this.type, required this.websiteUrl, required this.websiteKey});
  final String type;
  final String websiteUrl;
  final String websiteKey;
}

abstract class CaptchaClient {
  String get name;
  Future<String> solve(CaptchaTask task, {Duration timeout = const Duration(seconds: 180)});
}

class RuCaptchaClient implements CaptchaClient {
  RuCaptchaClient(this.apiKey, {http.Client? httpClient}) : _http = httpClient ?? http.Client();
  final String apiKey;
  final http.Client _http;
  @override
  String get name => 'rucaptcha';

  @override
  Future<String> solve(CaptchaTask task, {Duration timeout = const Duration(seconds: 180)}) async {
    final created = await _post('https://api.rucaptcha.com/createTask', {
      'clientKey': apiKey,
      'task': {
        'type': task.type,
        'websiteURL': task.websiteUrl,
        'websiteKey': task.websiteKey,
      },
    });
    final taskId = created['taskId'];
    if (created['errorId'] != 0 || taskId == null) {
      throw CaptchaSolveException('rucaptcha create failed');
    }
    return _poll('https://api.rucaptcha.com/getTaskResult', taskId, timeout);
  }

  Future<String> _poll(String url, Object taskId, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final body = await _post(url, {'clientKey': apiKey, 'taskId': taskId});
      if (body['errorId'] != 0) throw CaptchaSolveException('rucaptcha poll failed');
      if (body['status'] == 'ready') {
        final solution = body['solution'];
        if (solution is Map && solution['gRecaptchaResponse'] is String) {
          return solution['gRecaptchaResponse'] as String;
        }
        throw CaptchaSolveException('rucaptcha empty solution');
      }
    }
    throw CaptchaSolveException('rucaptcha timeout');
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> payload) async {
    final response = await _http.post(Uri.parse(url), headers: {'content-type': 'application/json'}, body: jsonEncode(payload));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CaptchaSolveException('rucaptcha http ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class CapMonsterClient implements CaptchaClient {
  CapMonsterClient(this.apiKey, {http.Client? httpClient}) : _http = httpClient ?? http.Client();
  final String apiKey;
  final http.Client _http;
  @override
  String get name => 'capmonster';

  @override
  Future<String> solve(CaptchaTask task, {Duration timeout = const Duration(seconds: 180)}) async {
    final created = await _post('https://api.capmonster.cloud/createTask', {
      'clientKey': apiKey,
      'task': {
        'type': task.type,
        'websiteURL': task.websiteUrl,
        'websiteKey': task.websiteKey,
      },
    });
    final taskId = created['taskId'];
    if (created['errorId'] != 0 || taskId == null) {
      throw CaptchaSolveException('capmonster create failed');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final body = await _post('https://api.capmonster.cloud/getTaskResult', {'clientKey': apiKey, 'taskId': taskId});
      if (body['errorId'] != 0) throw CaptchaSolveException('capmonster poll failed');
      if (body['status'] == 'ready') {
        final solution = body['solution'];
        if (solution is Map && solution['gRecaptchaResponse'] is String) {
          return solution['gRecaptchaResponse'] as String;
        }
        throw CaptchaSolveException('capmonster empty solution');
      }
    }
    throw CaptchaSolveException('capmonster timeout');
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> payload) async {
    final response = await _http.post(Uri.parse(url), headers: {'content-type': 'application/json'}, body: jsonEncode(payload));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CaptchaSolveException('capmonster http ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class CaptchaSolverService {
  CaptchaSolverService({List<CaptchaClient>? clients, String? ruCaptchaKey, String? capMonsterKey})
      : clients = clients ?? _fromKeys(ruCaptchaKey, capMonsterKey);

  final List<CaptchaClient> clients;

  static List<CaptchaClient> _fromKeys(String? ru, String? cap) {
    final list = <CaptchaClient>[];
    final ruKey = (ru ?? Platform.environment['RUCAPTCHA_KEY'] ?? '').trim();
    final capKey = (cap ?? Platform.environment['CAPMONSTER_KEY'] ?? '').trim();
    if (ruKey.isNotEmpty) list.add(RuCaptchaClient(ruKey));
    if (capKey.isNotEmpty) list.add(CapMonsterClient(capKey));
    return list;
  }

  Future<String?> solve(CaptchaTask task, {Duration timeout = const Duration(seconds: 180)}) async {
    Object? last;
    for (final client in clients) {
      try {
        return await client.solve(task, timeout: timeout);
      } catch (error) {
        last = error;
      }
    }
    if (last != null) return null;
    return null;
  }
}
