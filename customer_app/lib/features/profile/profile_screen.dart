import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
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
                      onTap: () => context.go('/home'),
                      child: const CircleAvatar(
                        backgroundColor: AppColors.white,
                        child: Icon(Icons.chevron_left_rounded, color: AppColors.primaryText),
                      ),
                    ),
                    const Text('Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    const CircleAvatar(
                      backgroundColor: AppColors.white,
                      child: Icon(Icons.settings_outlined, color: AppColors.primaryText, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(22)),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.secondaryCream,
                        child: Icon(Icons.person_rounded, color: AppColors.primaryOrange, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Harsh', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            Text('harsh@swiftroute.in', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.edit_note_rounded, color: AppColors.primaryText, size: 26),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _MenuGroupCard(items: [
                  _MenuItem(icon: Icons.person_outline_rounded, title: 'Profile Details', onTap: () {}),
                  _MenuItem(icon: Icons.receipt_long_outlined, title: 'My Orders', onTap: () => context.go('/orders')),
                  _MenuItem(icon: Icons.location_on_outlined, title: 'My Addresses', onTap: () {}),
                  _MenuItem(icon: Icons.account_balance_wallet_outlined, title: 'Payment Methods', onTap: () {}),
                  _MenuItem(icon: Icons.credit_card_outlined, title: 'Saved Cards', onTap: () {}),
                ]),
                const SizedBox(height: 16),
                _MenuGroupCard(items: [
                  _MenuItem(icon: Icons.notifications_none_rounded, title: 'Notifications', onTap: () {}),
                  _MenuItem(icon: Icons.dark_mode_outlined, title: 'Dark Mode', onTap: () {}),
                  _MenuItem(icon: Icons.help_outline_rounded, title: 'Help & Support', onTap: () {}),
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
                leading: Icon(item.icon, color: AppColors.secondaryText, size: 22),
                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.secondaryText),
                onTap: item.onTap,
              ),
            )
            .toList(),
      ),
    );
  }
}
