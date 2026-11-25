import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/network/dio_client.dart';
import '../../core/services/mapbox_geocoding_service.dart';
import '../../core/theme/app_theme.dart';

class PackageBookingWizard extends ConsumerStatefulWidget {
  const PackageBookingWizard({super.key});

  @override
  ConsumerState<PackageBookingWizard> createState() =>
      _PackageBookingWizardState();
}

class _PackageBookingWizardState extends ConsumerState<PackageBookingWizard> {
  int _step = 0;
  late Razorpay _razorpay;
  Timer? _debounce;

  // Sender & Pickup state
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _pickupSearchCtrl = TextEditingController();
  final _pickupAddr = TextEditingController();
  final _pickupCity = TextEditingController(text: 'Nanded');
  final _pickupPin = TextEditingController(text: '431601');
  double _pickupLat = 19.1383;
  double _pickupLng = 77.3210;
  List<MapboxPlace> _pickupSuggestions = [];
  bool _searchingPickup = false;
  bool _locatingPickup = false;

  // Receiver & Delivery state
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _deliverySearchCtrl = TextEditingController();
  final _deliveryAddr = TextEditingController();
  final _deliveryCity = TextEditingController(text: 'Pune');
  final _deliveryPin = TextEditingController(text: '411001');
  double _deliveryLat = 18.5204;
  double _deliveryLng = 73.8567;
  List<MapboxPlace> _deliverySuggestions = [];
  bool _searchingDelivery = false;

  // Package & Pricing state
  final _pkgName = TextEditingController();
  final _weightCtrl = TextEditingController(text: '1.5');
  final _promoCtrl = TextEditingController();
  String _category = 'Electronics';
  bool _isFragile = false;
  String _deliveryType = 'express';
  String _paymentMethod = 'online';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _razorpay.clear();
    _senderName.dispose();
    _senderPhone.dispose();
    _pickupSearchCtrl.dispose();
    _pickupAddr.dispose();
    _pickupCity.dispose();
    _pickupPin.dispose();
    _receiverName.dispose();
    _receiverPhone.dispose();
    _deliverySearchCtrl.dispose();
    _deliveryAddr.dispose();
    _deliveryCity.dispose();
    _deliveryPin.dispose();
    _pkgName.dispose();
    _weightCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, {required bool isPickup}) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        if (isPickup) {
          _pickupSuggestions = [];
        } else {
          _deliverySuggestions = [];
        }
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        if (isPickup) {
          _searchingPickup = true;
        } else {
          _searchingDelivery = true;
        }
      });

      final results = await ref.read(mapboxGeocodingProvider).searchPlaces(
            query,
            proximityLng: isPickup ? _pickupLng : _deliveryLng,
            proximityLat: isPickup ? _pickupLat : _deliveryLat,
          );

      if (!mounted) {
        return;
      }
      setState(() {
        if (isPickup) {
          _pickupSuggestions = results;
          _searchingPickup = false;
        } else {
          _deliverySuggestions = results;
          _searchingDelivery = false;
        }
      });
    });
  }

  void _selectPlace(MapboxPlace place, {required bool isPickup}) {
    setState(() {
      if (isPickup) {
        _pickupLat = place.latitude;
        _pickupLng = place.longitude;
        _pickupAddr.text = place.fullAddress;
        _pickupCity.text = place.city;
        _pickupPin.text = place.postalCode;
        _pickupSearchCtrl.text = place.name;
        _pickupSuggestions = [];
      } else {
        _deliveryLat = place.latitude;
        _deliveryLng = place.longitude;
        _deliveryAddr.text = place.fullAddress;
        _deliveryCity.text = place.city;
        _deliveryPin.text = place.postalCode;
        _deliverySearchCtrl.text = place.name;
        _deliverySuggestions = [];
      }
    });
  }

  Future<void> _useCurrentGpsForPickup() async {
    setState(() => _locatingPickup = true);
    try {
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings:
            const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      );
      final place = await ref.read(mapboxGeocodingProvider).reverseGeocode(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );

      if (!mounted) {
        return;
      }
      setState(() {
        _pickupLat = pos.latitude;
        _pickupLng = pos.longitude;
        if (place != null) {
          _pickupAddr.text = place.fullAddress;
          _pickupCity.text = place.city;
          _pickupPin.text = place.postalCode;
          _pickupSearchCtrl.text = place.name;
        } else {
          _pickupAddr.text =
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        }
        _pickupSuggestions = [];
      });
    } finally {
      if (mounted) {
        setState(() => _locatingPickup = false);
      }
    }
  }

  Future<void> _openPinDropPicker({required bool isPickup}) async {
    final initialLat = isPickup ? _pickupLat : _deliveryLat;
    final initialLng = isPickup ? _pickupLng : _deliveryLng;

    final selected = await Navigator.of(context).push<MapboxPlace>(
      MaterialPageRoute(
        builder: (_) => _MapboxPinDropScreen(
          title: isPickup ? 'Pin Pickup Location' : 'Pin Delivery Location',
          initialLat: initialLat,
          initialLng: initialLng,
        ),
      ),
    );

    if (selected != null && mounted) {
      _selectPlace(selected, isPickup: isPickup);
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    await ref.read(dioProvider).post('/payments/verify', data: {
      'razorpay_order_id': response.orderId,
      'razorpay_payment_id': response.paymentId,
      'razorpay_signature': response.signature,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Verified & Shipment Booked!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment Failed: ${response.message}'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _submitBooking() async {
    setState(() => _submitting = true);
    try {
      final routeEstimate = MapboxGeocodingService.estimateRoute(
        startLat: _pickupLat,
        startLng: _pickupLng,
        endLat: _deliveryLat,
        endLng: _deliveryLng,
      );

      final dio = ref.read(dioProvider);
      final res = await dio.post('/shipments', data: {
        'sender': {
          'name': _senderName.text.trim().isEmpty
              ? 'Customer'
              : _senderName.text.trim(),
          'phone': _senderPhone.text.trim().isEmpty
              ? '+919876543210'
              : _senderPhone.text.trim(),
        },
        'receiver': {
          'name': _receiverName.text.trim().isEmpty
              ? 'Receiver'
              : _receiverName.text.trim(),
          'phone': _receiverPhone.text.trim().isEmpty
              ? '+919876543211'
              : _receiverPhone.text.trim(),
        },
        'packageDetails': {
          'name': _pkgName.text.trim().isEmpty
              ? 'Standard Parcel'
              : _pkgName.text.trim(),
          'category': _category,
          'weightKg': double.tryParse(_weightCtrl.text) ?? 1.0,
          'isFragile': _isFragile,
        },
        'pickupLocation': {
          'coordinates': [_pickupLng, _pickupLat],
          'formattedAddress': _pickupAddr.text.trim().isEmpty
              ? _pickupCity.text
              : _pickupAddr.text.trim(),
          'city': _pickupCity.text.trim().isEmpty
              ? 'Origin'
              : _pickupCity.text.trim(),
          'postalCode': _pickupPin.text.trim().isEmpty
              ? '431601'
              : _pickupPin.text.trim(),
        },
        'deliveryLocation': {
          'coordinates': [_deliveryLng, _deliveryLat],
          'formattedAddress': _deliveryAddr.text.trim().isEmpty
              ? _deliveryCity.text
              : _deliveryAddr.text.trim(),
          'city': _deliveryCity.text.trim().isEmpty
              ? 'Destination'
              : _deliveryCity.text.trim(),
          'postalCode': _deliveryPin.text.trim().isEmpty
              ? '411001'
              : _deliveryPin.text.trim(),
        },
        'distanceKm': routeEstimate.distanceKm,
        'durationMinutes': routeEstimate.durationMinutes,
        'deliveryType': _deliveryType,
        'paymentMethod': _paymentMethod,
        'promoCode': _promoCtrl.text.trim(),
      });

      final shipment = res.data['shipment'];
      if (_paymentMethod == 'online') {
        final orderRes = await dio.post(
          '/payments/create-order',
          data: {'shipmentId': shipment['_id']},
        );
        _razorpay.open({
          'key': orderRes.data['keyId'],
          'amount': orderRes.data['amount'],
          'name': 'SwiftRoute Logistics',
          'order_id': orderRes.data['orderId'],
          'description': 'Shipment ${shipment['trackingId']}',
          'prefill': {'contact': _senderPhone.text},
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shipment Booked! Searching for courier...'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create booking. Check server connection.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildLocationPickerSection({
    required bool isPickup,
    required TextEditingController searchCtrl,
    required TextEditingController addrCtrl,
    required TextEditingController cityCtrl,
    required TextEditingController pinCtrl,
    required List<MapboxPlace> suggestions,
    required bool isSearching,
    required double lat,
    required double lng,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchCtrl,
          onChanged: (val) => _onSearchChanged(val, isPickup: isPickup),
          decoration: InputDecoration(
            hintText: isPickup
                ? 'Search pickup area, street, or city...'
                : 'Search delivery area, street, or city...',
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.primaryOrange,
            ),
            suffixIcon: isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          searchCtrl.clear();
                          setState(() {
                            if (isPickup) {
                              _pickupSuggestions = [];
                            } else {
                              _deliverySuggestions = [];
                            }
                          });
                        },
                      )
                    : null),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.background),
                itemBuilder: (context, idx) {
                  final item = suggestions[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primaryOrange,
                      size: 20,
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      item.fullAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => _selectPlace(item, isPickup: isPickup),
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (isPickup) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locatingPickup ? null : _useCurrentGpsForPickup,
                  icon: _locatingPickup
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: AppColors.primaryOrange,
                        ),
                  label: Text(
                    _locatingPickup ? 'Locating...' : 'Use Current GPS',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.secondaryCream),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openPinDropPicker(isPickup: isPickup),
                icon: const Icon(
                  Icons.map_outlined,
                  size: 18,
                  color: AppColors.primaryOrange,
                ),
                label: const Text('Pin on Map', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.secondaryCream,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: addrCtrl,
          decoration: InputDecoration(
            hintText: isPickup
                ? 'Full Pickup Street Address'
                : 'Full Delivery Street Address',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: cityCtrl,
                decoration: InputDecoration(
                  hintText: isPickup ? 'Pickup City' : 'Delivery City',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'PIN Code'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Pinned Coordinates: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
          style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = [
      'Sender & Pickup',
      'Receiver & Drop',
      'Package Info',
      'Delivery & Pay',
    ];
    final routeEstimate = MapboxGeocodingService.estimateRoute(
      startLat: _pickupLat,
      startLng: _pickupLng,
      endLat: _deliveryLat,
      endLng: _deliveryLng,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(stepTitles[_step]),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? AppColors.primaryOrange
                          : AppColors.secondaryCream,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (_step == 0) ...[
                      TextField(
                        controller: _senderName,
                        decoration:
                            const InputDecoration(hintText: 'Sender Full Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _senderPhone,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(hintText: 'Sender Phone'),
                      ),
                      const SizedBox(height: 14),
                      _buildLocationPickerSection(
                        isPickup: true,
                        searchCtrl: _pickupSearchCtrl,
                        addrCtrl: _pickupAddr,
                        cityCtrl: _pickupCity,
                        pinCtrl: _pickupPin,
                        suggestions: _pickupSuggestions,
                        isSearching: _searchingPickup,
                        lat: _pickupLat,
                        lng: _pickupLng,
                      ),
                    ],
                    if (_step == 1) ...[
                      TextField(
                        controller: _receiverName,
                        decoration: const InputDecoration(
                          hintText: 'Receiver Full Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _receiverPhone,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(hintText: 'Receiver Phone'),
                      ),
                      const SizedBox(height: 14),
                      _buildLocationPickerSection(
                        isPickup: false,
                        searchCtrl: _deliverySearchCtrl,
                        addrCtrl: _deliveryAddr,
                        cityCtrl: _deliveryCity,
                        pinCtrl: _deliveryPin,
                        suggestions: _deliverySuggestions,
                        isSearching: _searchingDelivery,
                        lat: _deliveryLat,
                        lng: _deliveryLng,
                      ),
                    ],
                    if (_step == 2) ...[
                      TextField(
                        controller: _pkgName,
                        decoration: const InputDecoration(
                          hintText: 'Package Name (e.g. Laptop)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: const [
                          DropdownMenuItem(
                            value: 'Electronics',
                            child: Text('Electronics'),
                          ),
                          DropdownMenuItem(
                            value: 'Documents',
                            child: Text('Documents'),
                          ),
                          DropdownMenuItem(
                            value: 'Apparel',
                            child: Text('Apparel'),
                          ),
                          DropdownMenuItem(
                            value: 'Fragile',
                            child: Text('Fragile'),
                          ),
                          DropdownMenuItem(
                            value: 'Food & Perishables',
                            child: Text('Food & Perishables'),
                          ),
                          DropdownMenuItem(
                            value: 'Other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _category = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _weightCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(hintText: 'Weight (Kg)'),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            title: const Text('Fragile Handling (+₹35)'),
                            activeThumbColor: AppColors.primaryOrange,
                            value: _isFragile,
                            onChanged: (v) => setState(() => _isFragile = v),
                          ),
                        ),
                      ),
                    ],
                    if (_step == 3) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryCream,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Route Summary',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  Text(
                                    '${_pickupCity.text} → ${_deliveryCity.text}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${routeEstimate.distanceKm} km',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryOrange,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '~${routeEstimate.durationMinutes} mins',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _deliveryType,
                        decoration:
                            const InputDecoration(labelText: 'Delivery Speed'),
                        items: const [
                          DropdownMenuItem(
                            value: 'standard',
                            child: Text('Standard Delivery (48 hrs)'),
                          ),
                          DropdownMenuItem(
                            value: 'express',
                            child: Text('Express Delivery (24 hrs)'),
                          ),
                          DropdownMenuItem(
                            value: 'same_day',
                            child: Text('Same-Day Priority (4 hrs)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _deliveryType = v);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration:
                            const InputDecoration(labelText: 'Payment Mode'),
                        items: const [
                          DropdownMenuItem(
                            value: 'online',
                            child: Text(
                              'Razorpay Online (UPI / Card / NetBanking)',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'cod',
                            child: Text('Cash on Delivery (COD)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _paymentMethod = v);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _promoCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Promo Code (Optional)',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 54),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            if (_step < 3) {
                              setState(() => _step++);
                            } else {
                              _submitBooking();
                            }
                          },
                    child: Text(
                      _step < 3
                          ? 'Continue'
                          : (_submitting ? 'Processing...' : 'Confirm & Pay'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapboxPinDropScreen extends ConsumerStatefulWidget {
  final String title;
  final double initialLat;
  final double initialLng;

  const _MapboxPinDropScreen({
    required this.title,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  ConsumerState<_MapboxPinDropScreen> createState() =>
      _MapboxPinDropScreenState();
}

class _MapboxPinDropScreenState extends ConsumerState<_MapboxPinDropScreen> {
  mapbox.MapboxMap? _mapboxMap;
  Timer? _panDebounce;
  late double _selectedLat;
  late double _selectedLng;
  MapboxPlace? _resolvedPlace;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLat;
    _selectedLng = widget.initialLng;
    _reverseLookup(_selectedLat, _selectedLng);
  }

  @override
  void dispose() {
    _panDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reverseLookup(double lat, double lng) async {
    setState(() => _resolving = true);
    final place = await ref
        .read(mapboxGeocodingProvider)
        .reverseGeocode(latitude: lat, longitude: lng);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedLat = lat;
      _selectedLng = lng;
      _resolvedPlace = place ??
          MapboxPlace(
            name: 'Pinned Location',
            fullAddress: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
            city: 'Nanded',
            postalCode: '431601',
            latitude: lat,
            longitude: lng,
          );
      _resolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          mapbox.MapWidget(
            key: const ValueKey('mapbox_pin_drop'),
            styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
            onMapCreated: (map) async {
              _mapboxMap = map;
              await map.setCamera(
                mapbox.CameraOptions(
                  center: mapbox.Point(
                    coordinates: mapbox.Position(_selectedLng, _selectedLat),
                  ),
                  zoom: 15.0,
                ),
              );
            },
            onCameraChangeListener: (_) async {
              if (_mapboxMap == null) {
                return;
              }
              final cam = await _mapboxMap!.getCameraState();
              final coords = cam.center.coordinates;
              final newLat = coords.lat.toDouble();
              final newLng = coords.lng.toDouble();
              if ((newLat - _selectedLat).abs() > 0.0002 ||
                  (newLng - _selectedLng).abs() > 0.0002) {
                setState(() {
                  _selectedLat = newLat;
                  _selectedLng = newLng;
                });
                _panDebounce?.cancel();
                _panDebounce = Timer(const Duration(milliseconds: 650), () {
                  if (mounted) {
                    _reverseLookup(_selectedLat, _selectedLng);
                  }
                });
              }
            },
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_on_rounded,
                size: 46,
                color: AppColors.primaryOrange,
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.darkSurface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Pan map to center the pin on your location, then confirm below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.white, fontSize: 12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Selected Address',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _reverseLookup(_selectedLat, _selectedLng),
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: AppColors.primaryOrange,
                        ),
                        label: const Text(
                          'Update Pin Address',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _resolving
                        ? 'Fetching address...'
                        : (_resolvedPlace?.fullAddress ?? ''),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _resolving || _resolvedPlace == null
                        ? null
                        : () => Navigator.of(context).pop(_resolvedPlace),
                    child: const Text('Confirm Pinned Location'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}