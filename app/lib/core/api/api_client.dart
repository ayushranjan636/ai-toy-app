import 'package:dio/dio.dart';

import 'api_error.dart';

/// Supplies and refreshes the parent's access token.
abstract interface class TokenProvider {
  Future<String?> accessToken();

  /// Try to refresh; returns the new token or null if the session is over.
  Future<String?> refreshAfterUnauthorized();

  /// Called when refresh fails: the app must sign out.
  void onSessionExpired();
}

/// Thin wrapper over Dio: bearer auth, one refresh on 401, typed errors.
/// Request/response bodies are never logged.
class ApiClient {
  ApiClient({required String baseUrl, required this._tokens, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              contentType: 'application/json',
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokens.accessToken();
          if (token != null) options.headers['authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final retried = error.requestOptions.extra['zRetried'] == true;
          if (status == 401 && !retried) {
            final fresh = await _tokens.refreshAfterUnauthorized();
            if (fresh != null) {
              final opts = error.requestOptions
                ..headers['authorization'] = 'Bearer $fresh'
                ..extra['zRetried'] = true;
              try {
                return handler.resolve(await _dio.fetch(opts));
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
            _tokens.onSessionExpired();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenProvider _tokens;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get<T>(path, queryParameters: query));

  Future<T> post<T>(String path, [Object? body]) => _wrap(() => _dio.post<T>(path, data: body));

  Future<T> put<T>(String path, Object body) => _wrap(() => _dio.put<T>(path, data: body));

  Future<T> patch<T>(String path, Object body) => _wrap(() => _dio.patch<T>(path, data: body));

  Future<void> delete(String path) => _wrap(() => _dio.delete<void>(path));

  Future<T> _wrap<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data as T;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
