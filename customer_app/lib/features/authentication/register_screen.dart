import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).post('/auth/register', data: {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: 'access_token', value: res.data['accessToken']);
      await storage.write(key: 'refresh_token', value: res.data['refreshToken']);
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration failed'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account'), backgroundColor: AppColors.background, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Full Name')),
              const SizedBox(height: 14),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email Address')),
              const SizedBox(height: 14),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(hintText: 'Phone Number (+91...)')),
              const SizedBox(height: 14),
              TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(hintText: 'Password')),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loading ? null : _register, child: Text(_loading ? 'Creating...' : 'Create Account')),
            ],
          ),
        ),
      ),
    );
  }
}
