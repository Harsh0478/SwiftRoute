import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/network/dio_client.dart';
import '../../core/providers/dev_mode_provider.dart';
import '../../core/services/fast_location_service.dart';
import '../../core/services/mapbox_geocoding_service.dart';
import '../../core/theme/app_theme.dart';

class PackageBookingWizard extends ConsumerStatefulWidget {
  const PackageBookingWizard({super.key});

  @override
  ConsumerState<PackageBookingWizard> createState() =>
      _PackageBookingWizardState();
}

class _PackageBookingWizardState extends ConsumerState<PackageBookingWizard> {
  static const double _searchRadiusKm = 18.0;

  int _step = 0;
  late Razorpay _razorpay;
  Timer? _debounce;

  final _step0FormKey = GlobalKey<FormState>();
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  // Sender & Pickup state
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _pickupSearchCtrl = TextEditingController();
  final _pickupAddr = TextEditingController();
  final _pickupCity = TextEditingController();
  final _pickupPin = TextEditingController();
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
  final _deliveryCity = TextEditingController();
  final _deliveryPin = TextEditingController();
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

  // Nearby courier check (used when Development Mode is OFF)
  bool _checkingNearbyAgents = false;
  int? _nearbyAgentsCount;
  String? _nearestAgentName;
  double? _nearestAgentDistanceKm;

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
        _nearbyAgentsCount = null;
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

      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please turn on device Location / GPS first.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      Future<void> applyPosition(geo.Position pos) async {
        final place = await ref.read(mapboxGeocodingProvider).reverseGeocode(
              latitude: pos.latitude,
              longitude: pos.longitude,
            );
        if (!mounted) return;
        setState(() {
          _pickupLat = pos.latitude;
          _pickupLng = pos.longitude;
          _nearbyAgentsCount = null;
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
      }

      // 1. Fill immediately from cached/last-known position if available
      final instantPos = await FastLocationService.getInstantPosition();
      if (instantPos != null) {
        await applyPosition(instantPos);
        if (mounted) setState(() => _locatingPickup = false);
      }

      // 2. Fetch fresh Wi-Fi/GPS position with a 4-second timeout (never hangs)
      final freshPos = await FastLocationService.getFastPosition(
        timeout: const Duration(seconds: 4),
      );
      if (freshPos != null) {
        await applyPosition(freshPos);
      } else if (instantPos == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not lock GPS signal. Try Pin on Map or search address.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
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

  Future<void> _checkNearbyCouriers() async {
    setState(() => _checkingNearbyAgents = true);
    try {
      final res = await ref.read(dioProvider).get(
        '/shipments/nearby-agents',
        queryParameters: {
          'lat': _pickupLat,
          'lng': _pickupLng,
          'radiusKm': _searchRadiusKm,
        },
      );
      if (!mounted) return;
      final nearest = res.data['nearestAgent'] as Map<String, dynamic>?;
      setState(() {
        _nearbyAgentsCount = (res.data['count'] as num?)?.toInt() ?? 0;
        _nearestAgentName = nearest?['name']?.toString();
        _nearestAgentDistanceKm =
            (nearest?['distanceKm'] as num?)?.toDouble();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nearbyAgentsCount = 0;
        _nearestAgentName = null;
        _nearestAgentDistanceKm = null;
      });
    } finally {
      if (mounted) {
        setState(() => _checkingNearbyAgents = false);
      }
    }
  }

  bool _validateCurrentStep() {
    if (_step == 0) {
      final valid = _step0FormKey.currentState?.validate() ?? false;
      if (!valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please fill in Sender Name, Phone, and Pickup Address before continuing.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return valid;
    }
    if (_step == 1) {
      final valid = _step1FormKey.currentState?.validate() ?? false;
      if (!valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please fill in Receiver Name, Phone, and Delivery Address before continuing.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return valid;
    }
    if (_step == 2) {
      final valid = _step2FormKey.currentState?.validate() ?? false;
      if (!valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter valid Package Name and Weight.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return valid;
    }
    return true;
  }

  void _handleContinue() {
    if (!_validateCurrentStep()) return;

    if (_step < 3) {
      final nextStep = _step + 1;
      setState(() {
        _step = nextStep;
        if (nextStep == 3) {
          final routeEstimate = MapboxGeocodingService.estimateRoute(
            startLat: _pickupLat,
            startLng: _pickupLng,
            endLat: _deliveryLat,
            endLng: _deliveryLng,
          );
          if (_deliveryType == 'same_day' && routeEstimate.distanceKm > 60.0) {
            _deliveryType = 'express';
          }
        }
      });

      if (nextStep == 3 && !ref.read(developmentModeProvider)) {
        _checkNearbyCouriers();
      }
    } else {
      _submitBooking();
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

  void _showNoCourierAvailableDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_searching_rounded,
                color: AppColors.error, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No Delivery Boy Nearby',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          'No online delivery partner is available within 18 km of your pickup location right now.You can retry searching, or enable Development Mode in Profile to send parcels directly during testing.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _checkNearbyCouriers();
            },
            child: const Text('Retry Search'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/profile');
            },
            child: const Text('Open Profile'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBooking() async {
    final isDevMode = ref.read(developmentModeProvider);

    if (!isDevMode) {
      await _checkNearbyCouriers();
      if (!mounted) return;
      if ((_nearbyAgentsCount ?? 0) <= 0) {
        _showNoCourierAvailableDialog();
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final routeEstimate = MapboxGeocodingService.estimateRoute(
        startLat: _pickupLat,
        startLng: _pickupLng,
        endLat: _deliveryLat,
        endLng: _deliveryLng,
      );
      final speedOptions =
          MapboxGeocodingService.calculateDeliverySpeedOptions(
        distanceKm: routeEstimate.distanceKm,
        weightKg: double.tryParse(_weightCtrl.text) ?? 1.0,
        isFragile: _isFragile,
      );
      final selectedSpeed = speedOptions.firstWhere(
        (opt) => opt.type == _deliveryType && opt.isAvailable,
        orElse: () => speedOptions.firstWhere((opt) => opt.type == 'express'),
      );

      final dio = ref.read(dioProvider);
      final res = await dio.post('/shipments', data: {
        'sender': {
          'name': _senderName.text.trim(),
          'phone': _senderPhone.text.trim(),
        },
        'receiver': {
          'name': _receiverName.text.trim(),
          'phone': _receiverPhone.text.trim(),
        },
        'packageDetails': {
          'name': _pkgName.text.trim(),
          'category': _category,
          'weightKg': double.tryParse(_weightCtrl.text) ?? 1.0,
          'isFragile': _isFragile,
        },
        'pickupLocation': {
          'coordinates': [_pickupLng, _pickupLat],
          'formattedAddress': _pickupAddr.text.trim(),
          'city': _pickupCity.text.trim(),
          'postalCode': _pickupPin.text.trim(),
        },
        'deliveryLocation': {
          'coordinates': [_deliveryLng, _deliveryLat],
          'formattedAddress': _deliveryAddr.text.trim(),
          'city': _deliveryCity.text.trim(),
          'postalCode': _deliveryPin.text.trim(),
        },
        'distanceKm': routeEstimate.distanceKm,
        'durationMinutes': selectedSpeed.estimatedMinutes,
        'deliveryType': selectedSpeed.type,
        'paymentMethod': _paymentMethod,
        'promoCode': _promoCtrl.text.trim(),
        'developmentMode': isDevMode,
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
          'prefill': {'contact': _senderPhone.text.trim()},
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
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      if (data is Map && data['code'] == 'NO_COURIER_NEARBY') {
        setState(() => _nearbyAgentsCount = 0);
        _showNoCourierAvailableDialog();
      } else {
        final msg = (data is Map && data['message'] != null)
            ? data['message'].toString()
            : 'Could not create booking. Check server connection.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
        );
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

  String? _requiredTextValidator(String? value, String label,
      {int minLength = 2}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '$label is required';
    }
    if (trimmed.length < minLength) {
      return '$label must be at least $minLength characters';
    }
    return null;
  }

  String? _phoneValidator(String? value, String label) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '$label is required';
    }
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }

  String? _pinValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'PIN required';
    }
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 4) {
      return 'Invalid PIN';
    }
    return null;
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
        TextFormField(
          controller: addrCtrl,
          validator: (v) => _requiredTextValidator(
            v,
            isPickup ? 'Pickup street address' : 'Delivery street address',
            minLength: 4,
          ),
          decoration: InputDecoration(
            labelText: isPickup
                ? 'Full Pickup Street Address *'
                : 'Full Delivery Street Address *',
            hintText: isPickup
                ? 'House/Flat, Street, Landmark'
                : 'House/Flat, Street, Landmark',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: cityCtrl,
                validator: (v) => _requiredTextValidator(
                  v,
                  isPickup ? 'Pickup city' : 'Delivery city',
                  minLength: 2,
                ),
                decoration: InputDecoration(
                  labelText: isPickup ? 'Pickup City *' : 'Delivery City *',
                  hintText: isPickup ? 'e.g. Amravati' : 'e.g. Pune',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                validator: _pinValidator,
                decoration: const InputDecoration(
                  labelText: 'PIN Code *',
                  hintText: '444601',
                ),
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
    final isDevMode = ref.watch(developmentModeProvider);
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
    final parsedWeight = double.tryParse(_weightCtrl.text) ?? 1.5;
    final speedOptions = MapboxGeocodingService.calculateDeliverySpeedOptions(
      distanceKm: routeEstimate.distanceKm,
      weightKg: parsedWeight,
      isFragile: _isFragile,
    );
    final effectiveDeliveryType = speedOptions.any(
      (opt) => opt.type == _deliveryType && opt.isAvailable,
    )
        ? _deliveryType
        : 'express';
    final selectedSpeedOption = speedOptions.firstWhere(
      (opt) => opt.type == effectiveDeliveryType,
      orElse: () => speedOptions.firstWhere((opt) => opt.type == 'express'),
    );

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) {
          setState(() => _step--);
        }
      },
      child: Scaffold(
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
                    if (_step == 0)
                      Form(
                        key: _step0FormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _senderName,
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  _requiredTextValidator(v, 'Sender full name'),
                              decoration: const InputDecoration(
                                labelText: 'Sender Full Name *',
                                hintText: 'Enter sender name',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _senderPhone,
                              keyboardType: TextInputType.phone,
                              validator: (v) =>
                                  _phoneValidator(v, 'Sender phone'),
                              decoration: const InputDecoration(
                                labelText: 'Sender Phone *',
                                hintText: '+91 9876543210',
                              ),
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
                        ),
                      ),
                    if (_step == 1)
                      Form(
                        key: _step1FormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _receiverName,
                              textCapitalization: TextCapitalization.words,
                              validator: (v) => _requiredTextValidator(
                                  v, 'Receiver full name'),
                              decoration: const InputDecoration(
                                labelText: 'Receiver Full Name *',
                                hintText: 'Enter receiver name',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _receiverPhone,
                              keyboardType: TextInputType.phone,
                              validator: (v) =>
                                  _phoneValidator(v, 'Receiver phone'),
                              decoration: const InputDecoration(
                                labelText: 'Receiver Phone *',
                                hintText: '+91 9876543211',
                              ),
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
                        ),
                      ),
                    if (_step == 2)
                      Form(
                        key: _step2FormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _pkgName,
                              validator: (v) =>
                                  _requiredTextValidator(v, 'Package name'),
                              decoration: const InputDecoration(
                                labelText: 'Package Name *',
                                hintText: 'e.g. Laptop, Documents',
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _category,
                              decoration:
                                  const InputDecoration(labelText: 'Category'),
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
                            TextFormField(
                              controller: _weightCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: (v) {
                                final w = double.tryParse(v?.trim() ?? '');
                                if (w == null || w <= 0) {
                                  return 'Enter a valid weight in Kg';
                                }
                                return null;
                              },
                              decoration: const InputDecoration(
                                labelText: 'Weight (Kg) *',
                                hintText: '1.5',
                              ),
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
                                  onChanged: (v) =>
                                      setState(() => _isFragile = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_step == 3) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryCream,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Route Summary',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                      Text(
                                        '${_pickupCity.text.trim()} → ${_deliveryCity.text.trim()}',
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
                                      'Est. ${selectedSpeedOption.etaLabel}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 18, color: Colors.black12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Speed: ~${selectedSpeedOption.averageSpeedKmh.round()} km/h avg',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                Text(
                                  'Total: ₹${selectedSpeedOption.estimatedTotalInr} (incl. GST)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppColors.primaryText,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!isDevMode)
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: _checkingNearbyAgents
                                ? AppColors.white
                                : ((_nearbyAgentsCount ?? 0) > 0
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : AppColors.error.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _checkingNearbyAgents
                                  ? AppColors.secondaryCream
                                  : ((_nearbyAgentsCount ?? 0) > 0
                                      ? AppColors.success
                                      : AppColors.error),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_checkingNearbyAgents)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                Icon(
                                  (_nearbyAgentsCount ?? 0) > 0
                                      ? Icons.check_circle_rounded
                                      : Icons.error_outline_rounded,
                                  color: (_nearbyAgentsCount ?? 0) > 0
                                      ? AppColors.success
                                      : AppColors.error,
                                  size: 20,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _checkingNearbyAgents
                                      ? 'Searching delivery partners within 18 km...'
                                      : ((_nearbyAgentsCount ?? 0) > 0
                                          ? '$_nearbyAgentsCount courier(s) nearby${_nearestAgentName != null ? ' • Nearest: $_nearestAgentName (${_nearestAgentDistanceKm?.toStringAsFixed(1)} km)' : ''}'
                                          : 'No delivery boy available within 18 km of pickup.'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _checkingNearbyAgents
                                        ? AppColors.primaryText
                                        : ((_nearbyAgentsCount ?? 0) > 0
                                            ? AppColors.success
                                            : AppColors.error),
                                  ),
                                ),
                              ),
                              if (!_checkingNearbyAgents)
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  tooltip: 'Re-check 18 km radius',
                                  onPressed: _checkNearbyCouriers,
                                ),
                            ],
                          ),
                        ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                            'speed_${routeEstimate.distanceKm}_$effectiveDeliveryType'),
                        initialValue: effectiveDeliveryType,
                        decoration: const InputDecoration(
                            labelText: 'Delivery Speed (Distance-Based)'),
                        items: speedOptions
                            .map(
                              (opt) => DropdownMenuItem<String>(
                                value: opt.type,
                                enabled: opt.isAvailable,
                                child: Text(
                                  opt.isAvailable
                                      ? '${opt.title} (${opt.etaLabel}) • ₹${opt.estimatedTotalInr}'
                                      : '${opt.title} (${opt.etaLabel})',
                                  style: TextStyle(
                                    color: opt.isAvailable
                                        ? AppColors.primaryText
                                        : AppColors.secondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
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
                    onPressed: _submitting ? null : _handleContinue,
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
            city: 'Amravati',
            postalCode: '444601',
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
