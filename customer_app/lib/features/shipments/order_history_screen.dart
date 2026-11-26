import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  String _selectedTab = 'All';
  final List<String> _tabs = ['All', 'In Progress', 'Delivered', 'Cancelled'];
  List<dynamic> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get('/shipments', queryParameters: {'status': _selectedTab});
      if (mounted) {
        setState(() {
          _orders = res.data['shipments'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [AppColors.secondaryCream, AppColors.background]),
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
                      onTap: () => context.go('/home'),
                      child: const CircleAvatar(backgroundColor: AppColors.white, child: Icon(Icons.chevron_left_rounded, color: AppColors.primaryText)),
                    ),
                    const Text('Order History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    const CircleAvatar(backgroundColor: AppColors.white, child: Icon(Icons.tune_rounded, color: AppColors.primaryText, size: 20)),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final isSelected = _selectedTab == tab;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedTab = tab);
                        _loadOrders();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(color: isSelected ? AppColors.primaryOrange : AppColors.white, borderRadius: BorderRadius.circular(22)),
                        child: Text(tab, style: TextStyle(color: isSelected ? AppColors.white : AppColors.primaryText, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _orders.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                                    child: const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primaryOrange),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('No Orders Found', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primaryText)),
                                  const SizedBox(height: 6),
                                  Text(
                                    _selectedTab == 'All'
                                        ? 'You have not booked any shipments yet.'
                                        : 'No shipments found under "$_selectedTab".',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: 200,
                                    child: ElevatedButton(
                                      onPressed: () => context.push('/booking').then((_) => _loadOrders()),
                                      child: const Text('Book a Shipment'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadOrders,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _orders.length,
                              itemBuilder: (context, index) {
                                final order = _orders[index];
                                final drop = order['deliveryLocation'] ?? {};
                                final status = order['shipmentStatus'] ?? 'Assigning Courier...';
                                final deliveryOtp = order['deliveryOtp']?.toString();
                                final showOtp = deliveryOtp != null &&
                                    deliveryOtp.isNotEmpty &&
                                    status != 'Delivered' &&
                                    status != 'Cancelled';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(22)),
                                  child: Column(
                                    children: [
                                      Row(children: [
                                        Container(
                                          width: 54,
                                          height: 54,
                                          decoration: BoxDecoration(color: AppColors.secondaryCream, borderRadius: BorderRadius.circular(16)),
                                          child: const Icon(Icons.local_shipping_rounded, color: AppColors.primaryOrange, size: 28),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text('Order #${order['trackingId']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                            Text(drop['city'] ?? 'Destination Hub', style: Theme.of(context).textTheme.bodySmall),
                                          ]),
                                        ),
                                        Text('₹${order['shippingCost']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                      ]),
                                      const SizedBox(height: 14),
                                      Row(children: [
                                        Expanded(
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.4)),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  status,
                                                  style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              if (showOtp)
                                                GestureDetector(
                                                  onTap: () {
                                                    Clipboard.setData(ClipboardData(text: deliveryOtp));
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Delivery OTP $deliveryOtp copied'),
                                                        duration: const Duration(seconds: 2),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.darkSurface,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.lock_outline_rounded, color: AppColors.primaryOrange, size: 12),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'OTP: $deliveryOtp',
                                                          style: const TextStyle(
                                                            color: AppColors.white,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            letterSpacing: 1,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => context.push('/track/${order['trackingId']}', extra: order),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                            decoration: BoxDecoration(color: AppColors.secondaryCream, borderRadius: BorderRadius.circular(16)),
                                            child: const Text('Track', style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w600, fontSize: 13)),
                                          ),
                                        ),
                                      ]),
                                    ],
                                  ),
                                );
                              },
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
