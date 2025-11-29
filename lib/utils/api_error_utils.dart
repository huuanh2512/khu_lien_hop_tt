import 'dart:convert';

import 'package:dio/dio.dart';

class ApiErrorDetails {
  const ApiErrorDetails({
    this.statusCode,
    this.message,
    this.raw,
  });

  final int? statusCode;
  final String? message;
  final String? raw;

  bool get isUnauthenticated => statusCode == 401;

  bool get isEmailNotVerified {
    if (statusCode != 403) return false;
    final lower = message?.toLowerCase() ?? '';
    return lower.contains('email not verified') || lower.contains('verify email');
  }
}

ApiErrorDetails parseApiError(Object error) {
  if (error is ApiErrorDetails) return error;
  if (error is DioException) {
    final response = error.response;
    final code = response?.statusCode;
    final message = _extractMessage(response?.data) ?? error.message;
    return ApiErrorDetails(statusCode: code, message: message, raw: error.toString());
  }

  final text = error.toString().trim();
  int? statusCode;
  String? message;

  final httpMatch = RegExp(r'HTTP\s+(\d{3})(?::\s*(.*))?').firstMatch(text);
  if (httpMatch != null) {
    statusCode = int.tryParse(httpMatch.group(1) ?? '');
    final rawBody = httpMatch.group(2)?.trim();
    if (rawBody != null && rawBody.isNotEmpty) {
      message = _extractBodyString(rawBody);
    }
  }

  final resolvedMessage = (message ?? _stripExceptionPrefix(text)).trim();
  final normalizedMessage = resolvedMessage.isEmpty ? null : resolvedMessage;

  return ApiErrorDetails(
    statusCode: statusCode,
    message: normalizedMessage,
    raw: text,
  );
}

String? _extractBodyString(String raw) {
  if (raw.isEmpty) return null;
  final parsed = _extractMessage(raw);
  if (parsed != null && parsed.isNotEmpty) {
    return parsed;
  }
  return raw;
}

String? _extractMessage(Object? data) {
  if (data == null) return null;
  if (data is String) {
    final trimmed = data.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        return _extractMessage(decoded) ?? trimmed;
      } catch (_) {
        return trimmed;
      }
    }
    return trimmed;
  }

  if (data is Map<String, dynamic>) {
    final keys = ['message', 'error', 'detail', 'description'];
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    final errors = data['errors'];
    if (errors is List) {
      final texts = errors
          .map((item) => item is String
              ? item
              : item is Map<String, dynamic>
                  ? item['message']?.toString()
                  : null)
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (texts.isNotEmpty) {
        return texts.join(', ');
      }
    }
    return data.toString();
  }

  if (data is List) {
    final texts = data
        .map((item) => item is String ? item : item.toString())
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (texts.isNotEmpty) {
      return texts.join(', ');
    }
  }

  return data.toString();
}

String _stripExceptionPrefix(String text) {
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) {
    return text.substring(prefix.length).trim();
  }
  return text;
}
