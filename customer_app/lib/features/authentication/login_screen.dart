import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).post('/auth/login', data: {
        'email': _emailCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: 'access_token', value: res.data['accessToken']);
      await storage.write(key: 'refresh_token', value: res.data['refreshToken']);
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Check credentials.'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.secondaryCream, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.local_shipping_rounded, color: AppColors.primaryOrange, size: 32),
              ),
              const SizedBox(height: 20),
              Text('Welcome Back', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text('Sign in to book and track your shipments', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 28),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email Address')),
              const SizedBox(height: 14),
              TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(hintText: 'Password')),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loading ? null : _login, child: Text(_loading ? 'Signing In...' : 'Sign In')),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('New to SwiftRoute? Create Account', style: TextStyle(color: AppColors.primaryOrange)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
