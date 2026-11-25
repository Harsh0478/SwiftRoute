import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    final token = await ref.read(secureStorageProvider).read(key: 'access_token');
    if (!mounted) return;
    context.go((token != null && token.isNotEmpty) ? '/home' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondaryCream,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: AppColors.primaryOrange, borderRadius: BorderRadius.circular(28)),
              child: const Icon(Icons.local_shipping_rounded, color: AppColors.white, size: 48),
            ),
            const SizedBox(height: 22),
            Text('SwiftRoute', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text('Fast, Trackable Doorstep Logistics', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
