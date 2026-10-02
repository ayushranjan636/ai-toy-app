import 'package:dio/dio.dart';

/// Typed API error with parent-facing message. Never contains secrets.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.details});

  final String code;
  final String message;
  final int? status;
  final Object? details;

  bool get isOffline => code == 'offline';
  bool get isSessionExpired => code == 'session_expired' || code == 'unauthenticated';
  bool get isConflict => status == 409;

  static const offline = ApiException('offline', "You're offline. Check your connection.");

  factory ApiException.fromDio(DioException e) {
    if (e.error is ApiException) return e.error as ApiException;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return offline;
      default:
        break;
    }
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        '${err['code']}',
        _friendly('${err['code']}', '${err['message']}'),
        status: e.response?.statusCode,
        details: err['details'],
      );
    }
    return ApiException(
      'http_${e.response?.statusCode ?? 0}',
      "Something went wrong on our side. Try again in a moment.",
      status: e.response?.statusCode,
    );
  }

  static String _friendly(String code, String fallback) => switch (code) {
    'validation_error' => 'Please check the details and try again.',
    'session_expired' => 'Your session has expired. Please sign in again.',
    'unauthenticated' => 'Please sign in again.',
    _ => fallback,
  };

  @override
  String toString() => 'ApiException($code, $status)';
}
