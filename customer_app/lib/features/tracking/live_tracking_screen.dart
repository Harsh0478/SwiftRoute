import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/dio_client.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String trackingId;
  final Map<String, dynamic>? initialShipment;
  const LiveTrackingScreen({super.key, required this.trackingId, this.initialShipment});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _polylineManager;
  CircleAnnotationManager? _circleManager;
  PolylineAnnotation? _routeAnnotation;
  CircleAnnotation? _agentAnnotation;

  Map<String, dynamic>? _shipment;
  double _agentLat = 19.1383;
  double _agentLng = 77.3210;
  double _pickupLat = 19.1383;
  double _pickupLng = 77.3210;
  double _destLat = 18.5204;
  double _destLng = 73.8567;
  String _status = 'Assigning Courier...';
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    if (widget.initialShipment != null) {
      _applyShipmentData(widget.initialShipment!);
      _bindSocket(widget.initialShipment!['_id']);
    } else {
      _loadShipment();
    }
  }

  Future<void> _ensureLocationPermission() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    final granted = permission == geo.LocationPermission.always || permission == geo.LocationPermission.whileInUse;
    if (mounted) {
      setState(() => _locationGranted = granted);
    }
    if (granted && _mapboxMap != null) {
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    }
  }

  Future<void> _loadShipment() async {
    final res = await ref.read(dioProvider).get('/shipments/track/${widget.trackingId}');
    if (!mounted) return;
    setState(() => _applyShipmentData(res.data['shipment']));
    _bindSocket(res.data['shipment']['_id']);
    await _drawMapAnnotations();
  }

  void _applyShipmentData(Map<String, dynamic> data) {
    final pCoords = data['pickupLocation']['coordinates'];
    final dCoords = data['deliveryLocation']['coordinates'];
    final cCoords = data['currentLocation']?['coordinates'] ?? pCoords;

    _shipment = data;
    _pickupLng = (pCoords[0] as num).toDouble();
    _pickupLat = (pCoords[1] as num).toDouble();
    _destLng = (dCoords[0] as num).toDouble();
    _destLat = (dCoords[1] as num).toDouble();
    _agentLng = (cCoords[0] as num).toDouble();
    _agentLat = (cCoords[1] as num).toDouble();
    _status = data['shipmentStatus'] ?? 'Assigning Courier...';
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    await mapboxMap.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(_agentLng, _agentLat)),
        zoom: 13.5,
      ),
    );

    if (_locationGranted) {
      await mapboxMap.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    }

    _polylineManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager = await mapboxMap.annotations.createCircleAnnotationManager();
    await _drawMapAnnotations();
  }

  Future<void> _drawMapAnnotations() async {
    if (_polylineManager == null || _circleManager == null) return;

    await _polylineManager!.deleteAll();
    await _circleManager!.deleteAll();

    _routeAnnotation = await _polylineManager!.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: [
            Position(_pickupLng, _pickupLat),
            Position(_agentLng, _agentLat),
            Position(_destLng, _destLat),
          ],
        ),
        lineColor: AppColors.primaryOrange.value,
        lineWidth: 5.0,
      ),
    );

    await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(_pickupLng, _pickupLat)),
        circleRadius: 7.5,
        circleColor: AppColors.white.value,
        circleStrokeWidth: 3.0,
        circleStrokeColor: AppColors.primaryOrange.value,
      ),
    );

    _agentAnnotation = await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(_agentLng, _agentLat)),
        circleRadius: 10.0,
        circleColor: AppColors.primaryOrange.value,
        circleStrokeWidth: 3.0,
        circleStrokeColor: AppColors.white.value,
      ),
    );

    await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(_destLng, _destLat)),
        circleRadius: 8.5,
        circleColor: AppColors.error.value,
        circleStrokeWidth: 3.0,
        circleStrokeColor: AppColors.white.value,
      ),
    );
  }

  Future<void> _bindSocket(String shipmentId) async {
    final socketSvc = ref.read(socketServiceProvider);
    await socketSvc.connect();
    socketSvc.joinShipmentRoom(shipmentId);

    socketSvc.socket?.on('shipment:location_updated', (data) async {
      if (!mounted) return;
      final newLat = (data['lat'] as num).toDouble();
      final newLng = (data['lng'] as num).toDouble();
      setState(() {
        _agentLat = newLat;
        _agentLng = newLng;
      });

      if (_agentAnnotation != null && _circleManager != null) {
        _agentAnnotation!.geometry = Point(coordinates: Position(newLng, newLat));
        await _circleManager!.update(_agentAnnotation!);
      }

      if (_routeAnnotation != null && _polylineManager != null) {
        _routeAnnotation!.geometry = LineString(
          coordinates: [
            Position(_pickupLng, _pickupLat),
            Position(newLng, newLat),
            Position(_destLng, _destLat),
          ],
        );
        await _polylineManager!.update(_routeAnnotation!);
      }

      await _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(newLng, newLat)),
          zoom: 14.0,
        ),
        MapAnimationOptions(duration: 800),
      );
    });

    socketSvc.socket?.on('shipment:status_updated', (data) {
      if (!mounted) return;
      setState(() => _status = data['shipmentStatus']);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_shipment == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final agent = _shipment!['deliveryAgentId'] as Map<String, dynamic>?;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: MapWidget(
              key: const ValueKey('mapbox_tracking_map'),
              styleUri: MapboxStyles.MAPBOX_STREETS,
              onMapCreated: _onMapCreated,
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CircleIconBtn(icon: Icons.arrow_back_rounded, onTap: () => context.pop()),
                    const Text(
                      'Location Tracking',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.primaryText),
                    ),
                    _CircleIconBtn(
                      icon: Icons.my_location_rounded,
                      onTap: () {
                        _mapboxMap?.flyTo(
                          CameraOptions(
                            center: Point(coordinates: Position(_agentLng, _agentLat)),
                            zoom: 14.2,
                          ),
                          MapAnimationOptions(duration: 600),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.50,
            minChildSize: 0.20,
            maxChildSize: 0.72,
            snap: true,
            snapSizes: const [0.20, 0.50, 0.72],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Booking Id:', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                            Text(
                              _shipment!['trackingId'],
                              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 22),
                            ),
                          ]),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: AppColors.darkSurfaceElevated, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              _status,
                              style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: List.generate(4, (i) {
                          final currentStep = _status == 'Delivered'
                              ? 3
                              : (_status == 'In Transit' || _status == 'Out for Delivery')
                                  ? 2
                                  : (_status == 'Order Confirmed' || _status == 'Package Picked Up')
                                      ? 1
                                      : 0;
                          final active = i <= currentStep;
                          return Expanded(
                            flex: i == 3 ? 0 : 1,
                            child: Row(children: [
                              Icon(
                                active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                color: active ? AppColors.primaryOrange : Colors.white30,
                                size: 18,
                              ),
                              if (i < 3)
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    color: i < currentStep ? AppColors.primaryOrange : Colors.white24,
                                  ),
                                ),
                            ]),
                          );
                        }),
                      ),
                      const SizedBox(height: 18),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 12),
                      _MetaRow(
                        leftLabel: 'From',
                        leftVal: _shipment!['pickupLocation']['city'],
                        rightLabel: 'To',
                        rightVal: _shipment!['deliveryLocation']['city'],
                      ),
                      const SizedBox(height: 12),
                      _MetaRow(
                        leftLabel: 'Customer',
                        leftVal: _shipment!['sender']['name'],
                        rightLabel: 'Order Cost',
                        rightVal: '₹${_shipment!['shippingCost']}',
                      ),
                      const SizedBox(height: 12),
                      _MetaRow(
                        leftLabel: 'Quantity',
                        leftVal: '${_shipment!['packageDetails']['quantity']} Box',
                        rightLabel: 'Weight',
                        rightVal: '${_shipment!['packageDetails']['weightKg']} Kg',
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.darkSurfaceElevated, borderRadius: BorderRadius.circular(32)),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.secondaryCream,
                              child: Icon(Icons.person_rounded, color: AppColors.primaryText),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  agent?['name'] ?? 'Assigning Courier...',
                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                const Text('Courier', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                              ]),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final phone = agent?['phone'];
                                if (phone != null) await launchUrl(Uri.parse('tel:$phone'));
                              },
                              child: const CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.primaryOrange,
                                child: Icon(Icons.call_rounded, color: AppColors.white, size: 19),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => context.push('/chat/${_shipment!['_id']}'),
                              child: const CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.white,
                                child: Icon(Icons.chat_bubble_rounded, color: AppColors.darkSurface, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
        child: Icon(icon, color: AppColors.primaryText, size: 20),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String leftLabel, leftVal, rightLabel, rightVal;
  const _MetaRow({required this.leftLabel, required this.leftVal, required this.rightLabel, required this.rightVal});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(leftLabel, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
          Text(leftVal, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rightLabel, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
          Text(rightVal, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    ]);
  }
}
