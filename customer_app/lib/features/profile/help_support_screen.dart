import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _trackingCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _selectedCategory = 'Shipment Delay';
  String _searchQuery = '';

  final List<String> _categories = [
    'Shipment Delay',
    'Courier Assignment',
    'Payment & Refund',
    'App Feedback',
    'Other',
  ];

  final List<Map<String, String>> _faqs = const [
    {
      'q': 'Why does it say "No delivery partner available within 18 km"?',
      'a': 'When Development Mode is OFF, SwiftRoute searches for active, online courier partners within an 18 km radius of your pinned pickup location. Make sure your pickup pin is set via GPS or Mapbox autocomplete, or enable Development Mode in Profile for direct testing.',
    },
    {
      'q': 'How does the 4-digit Delivery OTP work?',
      'a': 'Every booking generates a unique 4-digit Delivery OTP visible on your Order History and Live Tracking screens. Share this OTP with the courier partner only when they hand over your package at the destination.',
    },
    {
      'q': 'Can I cancel a shipment after booking?',
      'a': 'Yes. Shipments in "Assigning Courier...", "Order Confirmed", or "Package Picked Up" status can be cancelled from the tracking screen. Once a package is "In Transit" or "Out for Delivery", cancellation is locked.',
    },
    {
      'q': 'How are shipping charges and delivery times calculated?',
      'a': 'Charges are computed from route distance, parcel weight (surcharge above 2 kg), fragile handling, and delivery speed (Standard, Express, Same-Day, or Scheduled) plus 18% GST.',
    },
    {
      'q': 'How do I chat with my assigned delivery partner?',
      'a': 'Open your active order in Live Tracking and tap the Chat icon on the courier card to message your assigned partner in real time.',
    },
  ];

  @override
  void dispose() {
    _trackingCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchUri(Uri uri, String fallbackText) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fallbackText)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fallbackText)),
        );
      }
    }
  }

  void _submitTicket() {
    if (_messageCtrl.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your issue in at least 8 characters.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final ticketId = 'TKT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    _trackingCtrl.clear();
    _messageCtrl.clear();
    FocusScope.of(context).unfocus();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Text('Support Request Sent'),
          ],
        ),
        content: Text(
          'Your ticket ($ticketId) under "$_selectedCategory" has been logged. Our dispatch support team will reach out shortly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done',
                style: TextStyle(
                    color: AppColors.primaryOrange,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).cardColor;
    final primaryText = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.primaryText;

    final filteredFaqs = _faqs.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return item['q']!.toLowerCase().contains(q) ||
          item['a']!.toLowerCase().contains(q);
    }).toList();

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
                      'Help & Support',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quick contact cards
                      Row(
                        children: [
                          Expanded(
                            child: _ContactTile(
                              icon: Icons.phone_in_talk_rounded,
                              title: 'Call Desk',
                              subtitle: '+91 1800-120-4890',
                              onTap: () => _launchUri(
                                Uri.parse('tel:+9118001204890'),
                                'Support Desk: +91 1800-120-4890',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ContactTile(
                              icon: Icons.email_outlined,
                              title: 'Email Us',
                              subtitle: 'support@swiftroute.in',
                              onTap: () {
                                Clipboard.setData(const ClipboardData(
                                    text: 'support@swiftroute.in'));
                                _launchUri(
                                  Uri.parse(
                                      'mailto:support@swiftroute.in?subject=SwiftRoute%20Support'),
                                  'Copied support@swiftroute.in to clipboard',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('Frequently Asked Questions',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontSize: 16)),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Search FAQs (OTP, 18 km, cancel...)',
                          prefixIcon: Icon(Icons.search_rounded,
                              color: AppColors.secondaryText),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...filteredFaqs.map(
                        (faq) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Theme(
                            data: Theme.of(context)
                                .copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 16),
                              iconColor: AppColors.primaryOrange,
                              title: Text(
                                faq['q']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              children: [
                                Text(
                                  faq['a']!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        height: 1.45,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('Raise a Support Ticket',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontSize: 16)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _categories.map((cat) {
                                final selected = _selectedCategory == cat;
                                return ChoiceChip(
                                  label: Text(cat),
                                  selected: selected,
                                  selectedColor: AppColors.primaryOrange,
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? AppColors.white
                                        : primaryText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _selectedCategory = cat),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _trackingCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'Tracking ID (Optional, e.g. SR12345678)',
                                fillColor: isDark
                                    ? AppColors.darkBackground
                                    : AppColors.background,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _messageCtrl,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Describe your issue or question...',
                                fillColor: isDark
                                    ? AppColors.darkBackground
                                    : AppColors.background,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _submitTicket,
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: const Text('Submit Request'),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2E241E)
                    : AppColors.secondaryCream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryOrange, size: 22),
            ),
            const SizedBox(height: 10),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
