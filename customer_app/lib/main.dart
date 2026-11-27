import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'core/constants/api_constants.dart';
import 'core/providers/theme_provider.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assert(
    ApiConstants.mapboxPublicToken.isNotEmpty,
    'MAPBOX_ACCESS_TOKEN is empty. Run with --dart-define-from-file=.env',
  );
  MapboxOptions.setAccessToken(ApiConstants.mapboxPublicToken);
  runApp(const ProviderScope(child: SwiftRouteCustomerApp()));
}

class SwiftRouteCustomerApp extends ConsumerWidget {
  const SwiftRouteCustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'SwiftRoute Logistics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
