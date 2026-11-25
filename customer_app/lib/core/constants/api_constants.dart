class ApiConstants {
  // Emulator: 10.0.2.2 | Physical phone on same Wi-Fi: override in .env with your PC IPv4
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000/api',
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  // Loaded at build/run time via --dart-define-from-file=.env
  static const String mapboxPublicToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );
}