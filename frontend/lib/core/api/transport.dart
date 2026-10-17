import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/common.dart';

/// A failed request, with the backend's `detail` when it sent one.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// 503: the backend (or the AI behind it) is unavailable; screens fall back calmly.
  bool get unavailable => statusCode == 503 || statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// How requests reach the backend. The repository only talks to this.
abstract interface class ApiTransport {
  Future<Object?> get(String path, [Json query = const {}]);
  Future<Object?> put(String path, Json body);
}

class HttpTransport implements ApiTransport {
  HttpTransport(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path, Json query) => Uri.parse('$baseUrl$path').replace(
    queryParameters: query.isEmpty
        ? null
        : {for (final e in query.entries) e.key: e.value is List ? e.value : '${e.value}'},
  );

  @override
  Future<Object?> get(String path, [Json query = const {}]) =>
      _send(() => _client.get(_uri(path, query)));

  @override
  Future<Object?> put(String path, Json body) => _send(
    () => _client.put(
      _uri(path, const {}),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request();
    } on Exception catch (e) {
      throw ApiException('Could not reach the server ($e)');
    }
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final detail = body is Map ? body['detail'] : null;
    throw ApiException(
      detail is String ? detail : 'The server answered ${res.statusCode}',
      statusCode: res.statusCode,
    );
  }
}

/// Serves saved backend responses from assets/fixtures, for offline work and demos.
/// `/v1/alerts/detail` → `assets/fixtures/alerts_detail.json`. Params are ignored.
class FixtureTransport implements ApiTransport {
  FixtureTransport({this.latency = const Duration(milliseconds: 180)});

  final Duration latency;
  final Map<String, Object?> _saved = {};

  String _asset(String path) =>
      'assets/fixtures/${path.replaceFirst('/v1/', '').replaceAll(RegExp('[/-]'), '_')}.json';

  @override
  Future<Object?> get(String path, [Json query = const {}]) async {
    await Future<void>.delayed(latency);
    if (_saved.containsKey(path)) return _saved[path];
    try {
      return jsonDecode(await rootBundle.loadString(_asset(path), cache: false));
    } on Exception {
      throw ApiException('No fixture for $path', statusCode: 404);
    }
  }

  @override
  Future<Object?> put(String path, Json body) async {
    await Future<void>.delayed(latency);
    return _saved[path] = body;
  }
}
