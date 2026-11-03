/// Static app configuration.
///
/// Defaults to PRODUCTION (flaxxa.com) — real users log in with their flaxxa.com
/// credentials and hit the prod database. For local development/testing, build or
/// run with `--dart-define=PULSE_ENV=local` to point at this PC instead.
///
/// Notes for local mode:
/// - Android emulator reaches the PC's localhost via http://10.0.2.2
/// - A real phone/desktop needs a publicly reachable host (prod, or a tunnel).
class AppConfig {
  AppConfig._();

  /// Build-time environment: `prod` (default) or `local`.
  static const String environment =
      String.fromEnvironment('PULSE_ENV', defaultValue: 'prod');

  static bool get isLocal => environment == 'local';

  static const String apiPrefix = '/api/v1';

  /// Multi-tenancy header expected by the backend (ResolveTenant middleware).
  static const String tenantHeader = 'X-Tenant-ID';

  // ---- API base ----
  static String get apiBaseUrl =>
      isLocal ? 'http://localhost:8000' : 'https://flaxxa.com';

  // ---- Reverb (WebSocket) for live chat ----
  // Prod nginx proxies wss://flaxxa.com/app/{key}; local Reverb runs on :8085.
  static String get reverbScheme => isLocal ? 'ws' : 'wss';
  static String get reverbHost => isLocal ? '127.0.0.1' : 'flaxxa.com';
  static int get reverbPort => isLocal ? 8085 : 443;
  static String get reverbKey =>
      isLocal ? 'local-key' : '56ca94b07f90c4c24503fe0041ffff7b';
}
