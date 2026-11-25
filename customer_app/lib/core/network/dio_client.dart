import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await storage.read(key: 'access_token');
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      return handler.next(options);
    },
    onError: (DioException error, handler) async {
      if (error.response?.statusCode == 401 && error.requestOptions.path != '/auth/refresh-token') {
        final refreshToken = await storage.read(key: 'refresh_token');
        if (refreshToken != null) {
          try {
            final refreshDio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl));
            final res = await refreshDio.post('/auth/refresh-token', data: {'refreshToken': refreshToken});
            await storage.write(key: 'access_token', value: res.data['accessToken']);
            await storage.write(key: 'refresh_token', value: res.data['refreshToken']);
            error.requestOptions.headers['Authorization'] = 'Bearer ${res.data['accessToken']}';
            return handler.resolve(await dio.fetch(error.requestOptions));
          } catch (_) {
            await storage.deleteAll();
          }
        }
      }
      return handler.next(error);
    },
  ));

  return dio;
});
