import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/providers/dev_mode_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _name = 'Harsh';
  String _email = 'harsh@swiftroute.in';
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final storage = ref.read(secureStorageProvider);
    final cachedName = await storage.read(key: 'user_name');
    final cachedEmail = await storage.read(key: 'user_email');
    final cachedPhone = await storage.read(key: 'user_phone');
    if (mounted && (cachedName != null || cachedEmail != null)) {
      setState(() {
        _name = cachedName ?? _name;
        _email = cachedEmail ?? _email;
        _phone = cachedPhone ?? _phone;
      });
    }

    try {
      final res = await ref.read(dioProvider).get('/users/profile');
      final user = res.data['user'] as Map<String, dynamic>?;
      if (user != null && mounted) {
        final name = user['name']?.toString() ?? _name;
        final email = user['email']?.toString() ?? _email;
        final phone = user['phone']?.toString() ?? _phone;
        setState(() {
          _name = name;
          _email = email;
          _phone = phone;
        });
        await storage.write(key: 'user_name', value: name);
        await storage.write(key: 'user_email', value: email);
        await storage.write(key: 'user_phone', value: phone);
      }
    } catch (_) {
      // Keep cached/fallback profile values when offline
    }
  }

  Future<void> _openProfileDetails() async {
    final updated = await context.push<bool>('/profile/details');
    if (updated == true) {
      await _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDevMode = ref.watch(developmentModeProvider);
    final isDarkMode = ref.watch(themeModeProvider) == ThemeMode.dark;
    final cardBg = Theme.of(context).cardColor;
    final primaryText =
        Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.primaryText;

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.go('/home');
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: isDarkMode
                  ? [const Color(0xFF281F19), AppColors.darkBackground]
                  : [AppColors.secondaryCream, AppColors.background],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/home');
                          }
                        },
                        child: CircleAvatar(
                          backgroundColor: cardBg,
                          child: Icon(Icons.chevron_left_rounded,
                              color: primaryText),
                        ),
                      ),
                      const Text('Profile',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18)),
                      GestureDetector(
                        onTap: _openProfileDetails,
                        child: CircleAvatar(
                          backgroundColor: cardBg,
                          child: Icon(Icons.settings_outlined,
                              color: primaryText, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _openProfileDetails,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(22)),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: isDarkMode
                                ? const Color(0xFF2E241E)
                                : AppColors.secondaryCream,
                            child: const Icon(Icons.person_rounded,
                                color: AppColors.primaryOrange, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                                Text(_email,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                if (_phone.isNotEmpty)
                                  Text(_phone,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _openProfileDetails,
                            icon: Icon(Icons.edit_note_rounded,
                                color: primaryText, size: 26),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDevMode
                            ? AppColors.primaryOrange.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        secondary: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: isDevMode
                                ? AppColors.primaryOrange
                                    .withValues(alpha: 0.14)
                                : (isDarkMode
                                    ? const Color(0xFF2E241E)
                                    : AppColors.secondaryCream),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.developer_mode_rounded,
                            color: isDevMode
                                ? AppColors.primaryOrange
                                : AppColors.secondaryText,
                            size: 22,
                          ),
                        ),
                        title: Row(
                          children: [
                            const Text(
                              'Development Mode',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDevMode
                                    ? AppColors.primaryOrange
                                    : AppColors.secondaryText,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isDevMode ? 'ON' : 'OFF',
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            isDevMode
                                ? 'ON: Send parcels directly without nearby courier radius check.'
                                : 'OFF: Searches within 18 km radius; parcel can only be sent if a delivery partner is available.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 11.5),
                          ),
                        ),
                        activeThumbColor: AppColors.primaryOrange,
                        value: isDevMode,
                        onChanged: (val) async {
                          await ref
                              .read(developmentModeProvider.notifier)
                              .setEnabled(val);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                val
                                    ? 'Development Mode ON — direct parcel booking enabled'
                                    : 'Development Mode OFF — 18 km courier availability required',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MenuGroupCard(items: [
                    _MenuItem(
                        icon: Icons.person_outline_rounded,
                        title: 'Profile Details',
                        subtitle: 'Edit your name & mobile number',
                        onTap: _openProfileDetails),
                    _MenuItem(
                        icon: Icons.receipt_long_outlined,
                        title: 'My Orders',
                        subtitle: 'View active & past deliveries',
                        onTap: () => context.push('/orders')),
                  ]),
                  const SizedBox(height: 16),
                  Material(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: Icon(
                            isDarkMode
                                ? Icons.dark_mode_rounded
                                : Icons.dark_mode_outlined,
                            color: isDarkMode
                                ? AppColors.primaryOrange
                                : AppColors.secondaryText,
                            size: 22,
                          ),
                          title: const Text('Dark Mode',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 14)),
                          subtitle: Text(
                            isDarkMode ? 'Dark theme enabled' : 'Light theme enabled',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 11.5),
                          ),
                          activeThumbColor: AppColors.primaryOrange,
                          value: isDarkMode,
                          onChanged: (val) async {
                            await ref
                                .read(themeModeProvider.notifier)
                                .setDarkMode(val);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.help_outline_rounded,
                              color: AppColors.secondaryText, size: 22),
                          title: const Text('Help & Support',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 14)),
                          subtitle: Text(
                            'FAQs, support desk & issue reporting',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 11.5),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.secondaryText),
                          onTap: () => context.push('/help-support'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MenuGroupCard(items: [
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      title: 'Logout',
                      onTap: () async {
                        await ref.read(secureStorageProvider).delete(key: 'access_token');
                        await ref.read(secureStorageProvider).delete(key: 'refresh_token');
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}

class _MenuGroupCard extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuGroupCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: items
            .map(
              (item) => ListTile(
                leading:
                    Icon(item.icon, color: AppColors.secondaryText, size: 22),
                title: Text(item.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14)),
                subtitle: item.subtitle != null
                    ? Text(item.subtitle!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11.5))
                    : null,
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.secondaryText),
                onTap: item.onTap,
              ),
            )
            .toList(),
      ),
    );
  }
}
