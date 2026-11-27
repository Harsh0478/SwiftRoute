import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/providers/dev_mode_provider.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _name = 'Harsh';
  String _email = 'harsh@swiftroute.in';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final res = await ref.read(dioProvider).get('/users/profile');
      final user = res.data['user'] as Map<String, dynamic>?;
      if (user != null && mounted) {
        setState(() {
          _name = user['name']?.toString() ?? _name;
          _email = user['email']?.toString() ?? _email;
        });
      }
    } catch (_) {
      // Keep fallback profile values when offline
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDevMode = ref.watch(developmentModeProvider);

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.go('/home');
        }
      },
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [AppColors.secondaryCream, AppColors.background],
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
                      child: const CircleAvatar(
                        backgroundColor: AppColors.white,
                        child: Icon(Icons.chevron_left_rounded,
                            color: AppColors.primaryText),
                      ),
                    ),
                    const Text('Profile',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 18)),
                    const CircleAvatar(
                      backgroundColor: AppColors.white,
                      child: Icon(Icons.settings_outlined,
                          color: AppColors.primaryText, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(22)),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.secondaryCream,
                        child: Icon(Icons.person_rounded,
                            color: AppColors.primaryOrange, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                            Text(_email,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.edit_note_rounded,
                            color: AppColors.primaryText, size: 26),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
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
                              ? AppColors.primaryOrange.withValues(alpha: 0.14)
                              : AppColors.secondaryCream,
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
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.secondaryText),
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
                      onTap: () {}),
                  _MenuItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'My Orders',
                      onTap: () => context.go('/orders')),
                  _MenuItem(
                      icon: Icons.location_on_outlined,
                      title: 'My Addresses',
                      onTap: () {}),
                  _MenuItem(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Payment Methods',
                      onTap: () {}),
                  _MenuItem(
                      icon: Icons.credit_card_outlined,
                      title: 'Saved Cards',
                      onTap: () {}),
                ]),
                const SizedBox(height: 16),
                _MenuGroupCard(items: [
                  _MenuItem(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notifications',
                      onTap: () {}),
                  _MenuItem(
                      icon: Icons.dark_mode_outlined,
                      title: 'Dark Mode',
                      onTap: () {}),
                  _MenuItem(
                      icon: Icons.help_outline_rounded,
                      title: 'Help & Support',
                      onTap: () {}),
                ]),
                const SizedBox(height: 16),
                _MenuGroupCard(items: [
                  _MenuItem(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    onTap: () async {
                      await ref.read(secureStorageProvider).deleteAll();
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
  final VoidCallback onTap;
  _MenuItem({required this.icon, required this.title, required this.onTap});
}

class _MenuGroupCard extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuGroupCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
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
