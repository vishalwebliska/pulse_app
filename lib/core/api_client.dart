import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

/// Single typed HTTP client for the Flaxxa backend.
///
/// Every request automatically carries the Sanctum bearer token and the
/// `X-Tenant-ID` workspace header; writes also get an `Idempotency-Key`
/// so a retry never double-posts.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStore.instance.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final tenant = await TokenStore.instance.readTenant();
          if (tenant != null) {
            options.headers[AppConfig.tenantHeader] = tenant;
          }
          const writes = {'POST', 'PUT', 'PATCH', 'DELETE'};
          if (writes.contains(options.method.toUpperCase())) {
            options.headers['Idempotency-Key'] =
                '${DateTime.now().microsecondsSinceEpoch}-${options.path.hashCode}';
          }
          handler.next(options);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  Dio get dio => _dio;
}
