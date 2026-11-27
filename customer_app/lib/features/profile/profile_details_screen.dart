import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

class ProfileDetailsScreen extends ConsumerStatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  ConsumerState<ProfileDetailsScreen> createState() =>
      _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends ConsumerState<ProfileDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _isVerified = false;
  String _role = 'customer';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final storage = ref.read(secureStorageProvider);
    final cachedName = await storage.read(key: 'user_name');
    final cachedEmail = await storage.read(key: 'user_email');
    final cachedPhone = await storage.read(key: 'user_phone');

    if (mounted) {
      setState(() {
        _nameCtrl.text = cachedName ?? 'Harsh';
        _emailCtrl.text = cachedEmail ?? 'harsh@swiftroute.in';
        _phoneCtrl.text = cachedPhone ?? '';
      });
    }

    try {
      final res = await ref.read(dioProvider).get('/users/profile');
      final user = res.data['user'] as Map<String, dynamic>?;
      if (user != null && mounted) {
        final name = user['name']?.toString() ?? _nameCtrl.text;
        final email = user['email']?.toString() ?? _emailCtrl.text;
        final phone = user['phone']?.toString() ?? _phoneCtrl.text;
        setState(() {
          _nameCtrl.text = name;
          _emailCtrl.text = email;
          _phoneCtrl.text = phone;
          _isVerified = user['isVerified'] == true;
          _role = user['role']?.toString() ?? 'customer';
        });
        await storage.write(key: 'user_name', value: name);
        await storage.write(key: 'user_email', value: email);
        await storage.write(key: 'user_phone', value: phone);
      }
    } catch (_) {
      // Keep cached values when offline
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final updatedName = _nameCtrl.text.trim();
    final updatedPhone = _phoneCtrl.text.trim();

    try {
      await ref.read(dioProvider).put('/users/profile', data: {
        'name': updatedName,
        'phone': updatedPhone,
      });

      final storage = ref.read(secureStorageProvider);
      await storage.write(key: 'user_name', value: updatedName);
      await storage.write(key: 'user_phone', value: updatedPhone);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile details updated successfully'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update profile. Please check your connection or phone number.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'SR';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).cardColor;
    final primaryText = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.primaryText;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: isDark
                ? [const Color(0xFF281F19), AppColors.darkBackground]
                : [AppColors.secondaryCream, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: CircleAvatar(
                        backgroundColor: cardBg,
                        child: Icon(Icons.chevron_left_rounded, color: primaryText),
                      ),
                    ),
                    const Text(
                      'Profile Details',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 42,
                                      backgroundColor: isDark
                                          ? const Color(0xFF2E241E)
                                          : AppColors.secondaryCream,
                                      child: Text(
                                        _initials(_nameCtrl.text),
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primaryOrange,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryOrange
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _role.toUpperCase(),
                                            style: const TextStyle(
                                              color: AppColors.primaryOrange,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (_isVerified
                                                    ? AppColors.success
                                                    : AppColors.secondaryText)
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _isVerified
                                                    ? Icons.verified_rounded
                                                    : Icons.info_outline_rounded,
                                                size: 13,
                                                color: _isVerified
                                                    ? AppColors.success
                                                    : AppColors.secondaryText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _isVerified
                                                    ? 'Verified'
                                                    : 'Active Account',
                                                style: TextStyle(
                                                  color: _isVerified
                                                      ? AppColors.success
                                                      : AppColors.secondaryText,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text('Full Name',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: 'Enter your full name',
                                  prefixIcon: Icon(Icons.person_outline_rounded,
                                      color: AppColors.primaryOrange),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().length < 2) {
                                    return 'Please enter at least 2 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text('Phone Number',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: 'Enter 10-digit mobile number',
                                  prefixIcon: Icon(Icons.phone_outlined,
                                      color: AppColors.primaryOrange),
                                ),
                                validator: (v) {
                                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                                  if (digits.length < 10) {
                                    return 'Enter a valid 10-digit phone number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text('Email Address (Account ID)',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _emailCtrl,
                                readOnly: true,
                                enabled: false,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.email_outlined,
                                      color: AppColors.secondaryText),
                                ),
                              ),
                              const SizedBox(height: 28),
                              ElevatedButton.icon(
                                onPressed: _saving ? null : _saveProfile,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle_outline_rounded),
                                label: Text(
                                    _saving ? 'Saving Changes...' : 'Save Profile'),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
