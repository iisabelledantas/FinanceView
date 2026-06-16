import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/auth_repository.dart';
import '../config/app_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(authRepositoryProvider));
});

class ApiClient {
  final AuthRepository _authRepository;
  late final Dio _dio;

  ApiClient(this._authRepository) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout:
            const Duration(milliseconds: AppConfig.connectTimeoutMs),
        receiveTimeout:
            const Duration(milliseconds: AppConfig.receiveTimeoutMs),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authRepository.getAuthorizationToken();
          if (token != null) {
            options.headers['Authorization'] = token;
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _authRepository.signOut();
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    try {
      return await _dio.get(path, queryParameters: params);
    } on DioException catch (error) {
      throw ApiClientException.fromDio(error);
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    try {
      return await _dio.post(path, data: data);
    } on DioException catch (error) {
      throw ApiClientException.fromDio(error);
    }
  }
}

class ApiClientException implements Exception {
  final String message;

  const ApiClientException(this.message);

  factory ApiClientException.fromDio(DioException error) {
    final statusCode = error.response?.statusCode;

    if (statusCode == 401) {
      return const ApiClientException(
        'Sua sessão expirou. Faça login novamente.',
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return const ApiClientException(
        'O servidor está indisponível no momento. Tente novamente em instantes.',
      );
    }

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const ApiClientException(
        'Não foi possível conectar à API. Verifique sua conexão ou a configuração de CORS do backend.',
      );
    }

    return const ApiClientException(
      'Não foi possível carregar os dados. Tente novamente.',
    );
  }

  @override
  String toString() => message;
}
