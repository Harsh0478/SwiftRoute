import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'core/constants/api_constants.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(ApiConstants.mapboxPublicToken);
  runApp(const ProviderScope(child: SwiftRouteCustomerApp()));
}

class SwiftRouteCustomerApp extends StatelessWidget {
  const SwiftRouteCustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SwiftRoute Logistics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}
