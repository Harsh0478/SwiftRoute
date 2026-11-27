import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/services/mapbox_geocoding_service.dart';
import '../../core/theme/app_theme.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  List<dynamic> _shipments = [];
  bool _loading = true;
  String _currentAddress = 'Detecting location...';
  bool _locating = false;
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
    _fetchShipments();
  }

  Future<void> _detectCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _currentAddress = 'Location services disabled');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _currentAddress = 'Location permission denied');
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final place = await ref.read(mapboxGeocodingProvider).reverseGeocode(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );

      if (!mounted) return;
      setState(() {
        _currentAddress = place?.fullAddress ??
            '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _currentAddress = 'Tap to retry location');
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _fetchShipments() async {
    try {
      final res = await ref.read(dioProvider).get('/shipments');
      if (mounted) {
        setState(() {
          _shipments = res.data['shipments'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeShipment = _shipments.isNotEmpty ? _shipments.first : null;
    final recentShipments = _shipments.skip(1).take(4).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressAt == null ||
            now.difference(_lastBackPressAt!) > const Duration(seconds: 2)) {
          _lastBackPressAt = now;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit SwiftRoute'),
                duration: Duration(seconds: 2),
              ),
            );
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  _detectCurrentLocation(),
                  _fetchShipments(),
                ]);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: AppColors.primaryOrange,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: _detectCurrentLocation,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Current location',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (_locating) ...[
                                      const SizedBox(width: 6),
                                      const SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: AppColors.primaryOrange,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  _currentAddress,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColors.primaryText,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: const BoxDecoration(
                            color: AppColors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            color: AppColors.primaryText,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onSubmitted: (v) {
                              if (v.trim().isNotEmpty) context.push('/track/${v.trim()}');
                            },
                            decoration: const InputDecoration(
                              hintText: 'Search Tracking ID...',
                              prefixIcon: Icon(Icons.search_rounded, color: AppColors.secondaryText),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => context.push('/booking').then((_) => _fetchShipments()),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.darkSurface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickActionCard(
                            title: 'Send\nPackage',
                            bgColor: AppColors.white,
                            icon: Icons.local_shipping_rounded,
                            onTap: () => context.push('/booking').then((_) => _fetchShipments()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _QuickActionCard(
                            title: 'Track\nPackage',
                            bgColor: AppColors.secondaryCream,
                            icon: Icons.inventory_2_rounded,
                            onTap: () {
                              if (activeShipment != null) {
                                context.push('/track/${activeShipment['trackingId']}', extra: activeShipment);
                              } else {
                                context.push('/orders');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Current Shipment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16)),
                        GestureDetector(onTap: () => context.push('/orders'), child: Text('See All', style: Theme.of(context).textTheme.bodySmall)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                    else if (activeShipment != null)
                      _FeaturedShipmentCard(
                        shipment: activeShipment,
                        onTap: () => context.push('/track/${activeShipment['trackingId']}', extra: activeShipment),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
                        child: const Text('No active shipments yet. Tap "Send Package" to create your first booking!'),
                      ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Shipment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16)),
                        GestureDetector(onTap: () => context.push('/orders'), child: Text('See All', style: Theme.of(context).textTheme.bodySmall)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_loading && recentShipments.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
                        child: Text('No recent orders to display.', style: Theme.of(context).textTheme.bodySmall),
                      )
                    else
                      ...recentShipments.map((item) => _RecentShipmentTile(
                            shipment: item,
                            onTap: () => context.push('/track/${item['trackingId']}', extra: item),
                          )),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Container(
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _DockNavItem(icon: Icons.home_rounded, label: 'Home', isActive: true, onTap: () {}),
                    _DockNavItem(icon: Icons.inventory_2_outlined, label: 'Shipment', isActive: false, onTap: () => context.push('/orders')),
                    GestureDetector(
                      onTap: () => context.push('/booking').then((_) => _fetchShipments()),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.add_rounded, color: AppColors.darkSurface, size: 28),
                      ),
                    ),
                    _DockNavItem(
                      icon: Icons.near_me_outlined,
                      label: 'Tracking',
                      isActive: false,
                      onTap: () {
                        if (activeShipment != null) {
                          context.push('/track/${activeShipment['trackingId']}', extra: activeShipment);
                        } else {
                          context.push('/orders');
                        }
                      },
                    ),
                    _DockNavItem(icon: Icons.person_outline_rounded, label: 'Profile', isActive: false, onTap: () => context.push('/profile')),
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

class _QuickActionCard extends StatelessWidget {
  final String title;
  final Color bgColor;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickActionCard({required this.title, required this.bgColor, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 112,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.primaryText)),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryOrange, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedShipmentCard extends StatelessWidget {
  final Map<String, dynamic> shipment;
  final VoidCallback onTap;
  const _FeaturedShipmentCard({required this.shipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pkg = shipment['packageDetails'] ?? {};
    final pickup = shipment['pickupLocation'] ?? {};
    final drop = shipment['deliveryLocation'] ?? {};

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.devices_other_rounded, color: AppColors.primaryText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${shipment['trackingId']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(pkg['name'] ?? 'Express Parcel', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.secondaryCream, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    shipment['shipmentStatus'] ?? 'Assigning Courier...',
                    style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const CircleAvatar(radius: 6, backgroundColor: AppColors.primaryOrange),
                Expanded(child: Container(height: 2, color: AppColors.primaryOrange)),
                const CircleAvatar(radius: 6, backgroundColor: AppColors.primaryOrange),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Live GPS', style: TextStyle(fontSize: 10, color: AppColors.secondaryText)),
                      Container(height: 2, color: AppColors.background),
                    ],
                  ),
                ),
                const CircleAvatar(radius: 6, backgroundColor: AppColors.secondaryCream),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Origin', style: Theme.of(context).textTheme.bodySmall),
                    Text(pickup['city'] ?? 'Origin', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Destination', style: Theme.of(context).textTheme.bodySmall),
                    Text(drop['city'] ?? 'Destination', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentShipmentTile extends StatelessWidget {
  final Map<String, dynamic> shipment;
  final VoidCallback onTap;
  const _RecentShipmentTile({required this.shipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDelivered = shipment['shipmentStatus'] == 'Delivered';
    final pkg = shipment['packageDetails'] ?? {};
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.inventory_2_outlined, color: AppColors.primaryText, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${shipment['trackingId']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(pkg['name'] ?? 'Standard Box', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDelivered ? AppColors.success.withValues(alpha: 0.14) : AppColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                shipment['shipmentStatus'] ?? 'On Process',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDelivered ? AppColors.success : AppColors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _DockNavItem({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? AppColors.white : AppColors.secondaryText, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: isActive ? AppColors.white : AppColors.secondaryText)),
        ],
      ),
    );
  }
}
