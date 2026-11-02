import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.fields = const {}});
  final String message;
  final int? status;
  final Map<String, String> fields;
  @override
  String toString() => message;
}

/// Transport only. Session tokens stay in memory and are never logged.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8080/api',
          );
  final http.Client _client;
  final String baseUrl;
  String? token;

  Future<Object?> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path')
        .replace(queryParameters: query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      // Bound the entire response, including the body, to twenty seconds.
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 20));
      Object? data;
      if (response.body.isNotEmpty) {
        try {
          data = jsonDecode(response.body);
        } on FormatException {
          throw const ApiException(
            'The server returned an unreadable response.',
          );
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final json = data is Map<String, dynamic> ? data : <String, dynamic>{};
        throw ApiException(
          json['message'] as String? ?? 'Request failed. Please retry.',
          status: response.statusCode,
          fields: (json['errors'] as Map<String, dynamic>? ?? {}).map(
            (key, value) => MapEntry(key, value.toString()),
          ),
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException(
        'The server took too long. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the warehouse server. Check your connection.',
      );
    }
  }

  void close() => _client.close();
}
