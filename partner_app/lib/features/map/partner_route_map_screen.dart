import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/services/mapbox_directions_service.dart';

enum PartnerRouteLegMode {
  auto,
  toPickup,
  toDropoff,
  fullTrip,
}

class PartnerRouteMapScreen extends StatefulWidget {
  final String mapboxAccessToken;
  final geo.Position? currentPosition;
  final List<dynamic> assignments;
  final String? initialShipmentId;
  final bool isOnline;
  final Future<void> Function() onBroadcastLocationNow;
  final void Function(Map<String, dynamic> shipment) onOpenChat;
  final Future<void> Function(String shipmentId, String nextStatus) onAdvanceStatus;

  const PartnerRouteMapScreen({
    super.key,
    required this.mapboxAccessToken,
    required this.currentPosition,
    required this.assignments,
    this.initialShipmentId,
    required this.isOnline,
    required this.onBroadcastLocationNow,
    required this.onOpenChat,
    required this.onAdvanceStatus,
  });

  @override
  State<PartnerRouteMapScreen> createState() => _PartnerRouteMapScreenState();
}

class _PartnerRouteMapScreenState extends State<PartnerRouteMapScreen> {
  late final MapboxDirectionsService _directionsService;
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _polylineManager;
  CircleAnnotationManager? _circleManager;

  bool _isSatellite = false;
  bool _broadcasting = false;
  bool _loadingRoute = false;
  int _selectedIndex = 0;
  PartnerRouteLegMode _legMode = PartnerRouteLegMode.auto;

  PartnerNavigationRoute? _activeRoute;
  String? _lastRouteKey;
  geo.Position? _lastRoutedFromPos;

  @override
  void initState() {
    super.initState();
    _directionsService =
        MapboxDirectionsService(accessToken: widget.mapboxAccessToken);
    _syncSelectedIndex();
  }

  @override
  void didUpdateWidget(covariant PartnerRouteMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialShipmentId != null &&
        widget.initialShipmentId != oldWidget.initialShipmentId) {
      _syncSelectedIndex();
      _fetchRoute(force: true, fitCameraAfter: true);
      return;
    }

    if (_selectedIndex >= widget.assignments.length) {
      _selectedIndex = 0;
    }

    final shipmentChanged =
        oldWidget.assignments.length != widget.assignments.length;
    final movedSignificantly = _hasMovedBeyondThreshold(widget.currentPosition);

    if (shipmentChanged || movedSignificantly) {
      _fetchRoute(force: shipmentChanged, fitCameraAfter: shipmentChanged);
    } else if (oldWidget.currentPosition != widget.currentPosition) {
      _drawRouteAnnotations();
    }
  }

  bool _hasMovedBeyondThreshold(geo.Position? nextPos) {
    if (nextPos == null) return false;
    if (_lastRoutedFromPos == null) return true;
    final meters = geo.Geolocator.distanceBetween(
      _lastRoutedFromPos!.latitude,
      _lastRoutedFromPos!.longitude,
      nextPos.latitude,
      nextPos.longitude,
    );
    return meters >= 60.0;
  }

  void _syncSelectedIndex() {
    if (widget.initialShipmentId == null || widget.assignments.isEmpty) return;
    final idx = widget.assignments.indexWhere(
      (s) => s['_id']?.toString() == widget.initialShipmentId,
    );
    if (idx >= 0) _selectedIndex = idx;
  }

  Map<String, dynamic>? get _activeShipment {
    if (widget.assignments.isEmpty) return null;
    if (_selectedIndex < 0 || _selectedIndex >= widget.assignments.length) {
      return Map<String, dynamic>.from(widget.assignments.first);
    }
    return Map<String, dynamic>.from(widget.assignments[_selectedIndex]);
  }

  PartnerRouteLegMode _resolvedLegMode(Map<String, dynamic> shipment) {
    if (_legMode != PartnerRouteLegMode.auto) return _legMode;
    final status = shipment['shipmentStatus']?.toString() ?? 'Order Confirmed';
    if (status == 'Assigning Courier...' ||
        status == 'Order Confirmed' ||
        status == 'Going to Collect Package') {
      return PartnerRouteLegMode.toPickup;
    }
    return PartnerRouteLegMode.toDropoff;
  }

  String _resolvedDestinationTitle(Map<String, dynamic> shipment) {
    final mode = _resolvedLegMode(shipment);
    switch (mode) {
      case PartnerRouteLegMode.toPickup:
        return 'Heading to Pickup';
      case PartnerRouteLegMode.toDropoff:
        return 'Heading to Drop-off';
      case PartnerRouteLegMode.fullTrip:
        return 'Full Route (Pickup → Drop-off)';
      case PartnerRouteLegMode.auto:
        return 'Active Route';
    }
  }

  List<Position> _buildWaypoints(Map<String, dynamic> shipment) {
    final pos = widget.currentPosition;
    final pCoords = shipment['pickupLocation']?['coordinates'] as List?;
    final dCoords = shipment['deliveryLocation']?['coordinates'] as List?;

    if (pCoords == null ||
        pCoords.length < 2 ||
        dCoords == null ||
        dCoords.length < 2) {
      return [];
    }

    final pickupPos = Position(
      (pCoords[0] as num).toDouble(),
      (pCoords[1] as num).toDouble(),
    );
    final dropoffPos = Position(
      (dCoords[0] as num).toDouble(),
      (dCoords[1] as num).toDouble(),
    );

    final mode = _resolvedLegMode(shipment);

    if (pos == null) {
      return [pickupPos, dropoffPos];
    }

    final courierPos = Position(pos.longitude, pos.latitude);

    switch (mode) {
      case PartnerRouteLegMode.toPickup:
        return [courierPos, pickupPos];
      case PartnerRouteLegMode.toDropoff:
        return [courierPos, dropoffPos];
      case PartnerRouteLegMode.fullTrip:
      case PartnerRouteLegMode.auto:
        return [courierPos, pickupPos, dropoffPos];
    }
  }

  Future<void> _fetchRoute({
    bool force = false,
    bool fitCameraAfter = true,
  }) async {
    final shipment = _activeShipment;
    if (shipment == null) {
      if (mounted) {
        setState(() {
          _activeRoute = null;
          _lastRouteKey = null;
        });
      }
      await _drawRouteAnnotations();
      return;
    }

    final waypoints = _buildWaypoints(shipment);
    if (waypoints.length < 2) return;

    final routeKey =
        '${shipment['_id']}_${_resolvedLegMode(shipment).name}_${waypoints.map((w) => '${w.lng.toStringAsFixed(4)},${w.lat.toStringAsFixed(4)}').join(';')}';

    if (!force && routeKey == _lastRouteKey && _activeRoute != null) {
      await _drawRouteAnnotations();
      return;
    }

    if (mounted) setState(() => _loadingRoute = true);

    try {
      final fetched = await _directionsService.getRoute(waypoints: waypoints);
      if (!mounted) return;
      setState(() {
        _activeRoute = fetched;
        _lastRouteKey = routeKey;
        _lastRoutedFromPos = widget.currentPosition;
        _loadingRoute = false;
      });
      await _drawRouteAnnotations();
      if (fitCameraAfter) {
        await _fitCamera(animate: true);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
      await _drawRouteAnnotations();
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    await mapboxMap.compass.updateSettings(
      CompassSettings(
        enabled: true,
        position: OrnamentPosition.TOP_RIGHT,
        marginTop: 185.0,
        marginRight: 16.0,
      ),
    );

    await mapboxMap.scaleBar.updateSettings(
      ScaleBarSettings(enabled: false),
    );

    if (widget.currentPosition != null) {
      await mapboxMap.location.updateSettings(
        LocationComponentSettings(enabled: true, pulsingEnabled: true),
      );
    }

    _polylineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();

    await _fetchRoute(force: true, fitCameraAfter: true);
  }

  Future<void> _toggleStyle() async {
    if (_mapboxMap == null) return;
    setState(() => _isSatellite = !_isSatellite);
    await _mapboxMap!.loadStyleURI(
      _isSatellite
          ? MapboxStyles.SATELLITE_STREETS
          : MapboxStyles.MAPBOX_STREETS,
    );
    _polylineManager =
        await _mapboxMap!.annotations.createPolylineAnnotationManager();
    _circleManager =
        await _mapboxMap!.annotations.createCircleAnnotationManager();
    await _drawRouteAnnotations();
  }

  Future<void> _drawRouteAnnotations() async {
    if (_polylineManager == null || _circleManager == null) return;

    await _polylineManager!.deleteAll();
    await _circleManager!.deleteAll();

    final pos = widget.currentPosition;
    final shipment = _activeShipment;

    if (shipment != null) {
      final pCoords = shipment['pickupLocation']?['coordinates'] as List?;
      final dCoords = shipment['deliveryLocation']?['coordinates'] as List?;

      final routeCoords = (_activeRoute != null &&
              _activeRoute!.coordinates.length >= 2)
          ? _activeRoute!.coordinates
          : _buildWaypoints(shipment);

      if (routeCoords.length >= 2) {
        // Dark outer casing for high contrast on streets & satellite
        await _polylineManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: routeCoords),
            lineColor: const Color(0xFF1A1D24).value,
            lineWidth: 8.5,
          ),
        );

        // Primary SwiftRoute orange road path
        await _polylineManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: routeCoords),
            lineColor: const Color(0xFFF99A4F).value,
            lineWidth: 5.5,
          ),
        );
      }

      if (pCoords != null && pCoords.length >= 2) {
        final pLng = (pCoords[0] as num).toDouble();
        final pLat = (pCoords[1] as num).toDouble();
        await _circleManager!.create(
          CircleAnnotationOptions(
            geometry: Point(coordinates: Position(pLng, pLat)),
            circleRadius: 9.0,
            circleColor: const Color(0xFF42B883).value,
            circleStrokeWidth: 3.0,
            circleStrokeColor: Colors.white.value,
          ),
        );
      }

      if (dCoords != null && dCoords.length >= 2) {
        final dLng = (dCoords[0] as num).toDouble();
        final dLat = (dCoords[1] as num).toDouble();
        await _circleManager!.create(
          CircleAnnotationOptions(
            geometry: Point(coordinates: Position(dLng, dLat)),
            circleRadius: 9.0,
            circleColor: const Color(0xFFE53935).value,
            circleStrokeWidth: 3.0,
            circleStrokeColor: Colors.white.value,
          ),
        );
      }
    }

    if (pos != null) {
      await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(pos.longitude, pos.latitude)),
          circleRadius: 11.0,
          circleColor: const Color(0xFFF99A4F).value,
          circleStrokeWidth: 3.5,
          circleStrokeColor: Colors.white.value,
        ),
      );
    }
  }

  Future<void> _fitCamera({bool animate = true}) async {
    if (_mapboxMap == null) return;

    final points = <Point>[];
    if (_activeRoute != null && _activeRoute!.coordinates.length >= 2) {
      for (final coord in _activeRoute!.coordinates) {
        points.add(Point(coordinates: coord));
      }
    } else {
      final pos = widget.currentPosition;
      if (pos != null) {
        points.add(Point(coordinates: Position(pos.longitude, pos.latitude)));
      }
      final shipment = _activeShipment;
      if (shipment != null) {
        for (final wp in _buildWaypoints(shipment)) {
          points.add(Point(coordinates: wp));
        }
      }
    }

    if (points.isEmpty) return;

    if (points.length == 1) {
      final cam = CameraOptions(center: points.first, zoom: 15.2);
      if (animate) {
        await _mapboxMap!.flyTo(cam, MapAnimationOptions(duration: 700));
      } else {
        await _mapboxMap!.setCamera(cam);
      }
      return;
    }

    final cameraOptions = await _mapboxMap!.cameraForCoordinates(
      points,
      MbxEdgeInsets(top: 195.0, left: 52.0, bottom: 295.0, right: 52.0),
      null,
      null,
    );

    final clampedZoom =
        (cameraOptions.zoom != null && cameraOptions.zoom! > 16.0)
            ? 16.0
            : cameraOptions.zoom;

    final fitted = CameraOptions(
      center: cameraOptions.center,
      zoom: clampedZoom,
      bearing: cameraOptions.bearing,
      pitch: cameraOptions.pitch,
    );

    if (animate) {
      await _mapboxMap!.flyTo(fitted, MapAnimationOptions(duration: 750));
    } else {
      await _mapboxMap!.setCamera(fitted);
    }
  }

  Future<void> _handleBroadcastAndReroute() async {
    if (_broadcasting) return;
    setState(() => _broadcasting = true);
    try {
      await widget.onBroadcastLocationNow();
      await _fetchRoute(force: true, fitCameraAfter: true);
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  IconData _maneuverIcon(RouteStepInstruction step) {
    final type = step.maneuverType.toLowerCase();
    final mod = step.maneuverModifier.toLowerCase();

    if (type == 'arrive') return Icons.flag_rounded;
    if (type == 'depart') return Icons.navigation_rounded;
    if (type.contains('roundabout') || type.contains('rotary')) {
      return Icons.roundabout_right_rounded;
    }
    if (mod.contains('uturn')) return Icons.u_turn_left_rounded;
    if (mod.contains('sharp left') || mod == 'left') {
      return Icons.turn_left_rounded;
    }
    if (mod.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (mod.contains('sharp right') || mod == 'right') {
      return Icons.turn_right_rounded;
    }
    if (mod.contains('slight right')) return Icons.turn_slight_right_rounded;
    return Icons.straight_rounded;
  }

  void _showTurnByTurnSheet() {
    final route = _activeRoute;
    final shipment = _activeShipment;
    if (route == null || route.steps.isEmpty || shipment == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1D24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.88,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _resolvedDestinationTitle(shipment),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${route.formattedDistance} • ${route.formattedDuration} • ETA ${route.etaClockTime}',
                          style: const TextStyle(
                            color: Color(0xFF42B883),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: route.steps.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white10, height: 18),
                itemBuilder: (_, idx) {
                  final step = route.steps[idx];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: idx == 0
                              ? const Color(0xFFF99A4F)
                              : const Color(0xFF282C37),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _maneuverIcon(step),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.instruction,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (step.streetName.isNotEmpty)
                              Text(
                                step.streetName,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        step.formattedDistance,
                        style: const TextStyle(
                          color: Color(0xFFF99A4F),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nextStatusLabel(String status) {
    switch (status) {
      case 'Assigning Courier...':
        return 'Accept Order';
      case 'Order Confirmed':
        return 'Going to Collect Package';
      case 'Going to Collect Package':
        return 'Mark Picked Up';
      case 'Package Picked Up':
        return 'Start Transit';
      case 'In Transit':
      case 'Processing at Facility':
        return 'Out for Delivery';
      case 'Out for Delivery':
        return 'Complete (OTP)';
      default:
        return 'Out for Delivery';
    }
  }

  String _nextStatusValue(String status) {
    switch (status) {
      case 'Assigning Courier...':
        return 'Order Confirmed';
      case 'Order Confirmed':
        return 'Going to Collect Package';
      case 'Going to Collect Package':
        return 'Package Picked Up';
      case 'Package Picked Up':
        return 'In Transit';
      case 'In Transit':
      case 'Processing at Facility':
        return 'Out for Delivery';
      case 'Out for Delivery':
        return 'Delivered';
      default:
        return 'Out for Delivery';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.currentPosition;
    final shipment = _activeShipment;
    final nextStep = (_activeRoute != null && _activeRoute!.steps.isNotEmpty)
        ? _activeRoute!.steps.first
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        MapWidget(
          key: const ValueKey('partner_live_route_map'),
          styleUri: MapboxStyles.MAPBOX_STREETS,
          onMapCreated: _onMapCreated,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (nextStep != null && shipment != null)
                  GestureDetector(
                    onTap: _showTurnByTurnSheet,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D24),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFF99A4F).withValues(alpha: 0.5),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF99A4F),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              _maneuverIcon(nextStep),
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nextStep.instruction,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'In ${nextStep.formattedDistance} • Tap for ${_activeRoute!.steps.length} turn-by-turn steps',
                                  style: const TextStyle(
                                    color: Color(0xFF42B883),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.format_list_numbered_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1D24),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 18,
                              color: widget.isOnline
                                  ? const Color(0xFF42B883)
                                  : const Color(0xFFF99A4F),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pos != null
                                    ? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)} • ${(pos.speed * 3.6).clamp(0, 180).toStringAsFixed(0)} km/h'
                                    : 'Waiting for GPS fix...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MapActionBtn(
                      icon: Icons.layers_rounded,
                      active: _isSatellite,
                      onTap: _toggleStyle,
                    ),
                    const SizedBox(width: 8),
                    _MapActionBtn(
                      icon: Icons.center_focus_strong_rounded,
                      onTap: () => _fitCamera(animate: true),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (shipment != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1D24),
                          foregroundColor: Colors.white,
                          elevation: 3,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _loadingRoute
                            ? null
                            : () => _fetchRoute(force: true, fitCameraAfter: true),
                        icon: _loadingRoute
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFF99A4F),
                                ),
                              )
                            : const Icon(
                                Icons.alt_route_rounded,
                                size: 17,
                                color: Color(0xFFF99A4F),
                              ),
                        label: Text(
                          _loadingRoute ? 'Routing...' : 'Refresh Route',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF99A4F),
                        foregroundColor: Colors.white,
                        elevation: 3,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed:
                          _broadcasting ? null : _handleBroadcastAndReroute,
                      icon: _broadcasting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.gps_fixed_rounded, size: 17),
                      label: Text(
                        _broadcasting ? 'Syncing...' : 'Update GPS',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: shipment == null
              ? Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D24),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.explore_outlined,
                          color: Color(0xFFF99A4F), size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No active route right now. Your live GPS pin is ready for incoming pickups.',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D24),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.assignments.length > 1) ...[
                        SizedBox(
                          height: 30,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.assignments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, idx) {
                              final item = widget.assignments[idx];
                              final selected = idx == _selectedIndex;
                              return ChoiceChip(
                                label: Text(
                                  item['trackingId']?.toString() ?? 'Order',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: const Color(0xFFF99A4F),
                                onSelected: (_) async {
                                  setState(() => _selectedIndex = idx);
                                  await _fetchRoute(
                                      force: true, fitCameraAfter: true);
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Route Leg Switcher (Auto / Pickup / Drop-off / Full Trip)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _LegChip(
                              label: 'Auto Leg',
                              selected: _legMode == PartnerRouteLegMode.auto,
                              onTap: () {
                                setState(
                                    () => _legMode = PartnerRouteLegMode.auto);
                                _fetchRoute(force: true, fitCameraAfter: true);
                              },
                            ),
                            const SizedBox(width: 6),
                            _LegChip(
                              label: 'To Pickup',
                              selected:
                                  _legMode == PartnerRouteLegMode.toPickup,
                              onTap: () {
                                setState(() =>
                                    _legMode = PartnerRouteLegMode.toPickup);
                                _fetchRoute(force: true, fitCameraAfter: true);
                              },
                            ),
                            const SizedBox(width: 6),
                            _LegChip(
                              label: 'To Drop-off',
                              selected:
                                  _legMode == PartnerRouteLegMode.toDropoff,
                              onTap: () {
                                setState(() =>
                                    _legMode = PartnerRouteLegMode.toDropoff);
                                _fetchRoute(force: true, fitCameraAfter: true);
                              },
                            ),
                            const SizedBox(width: 6),
                            _LegChip(
                              label: 'Full Trip',
                              selected:
                                  _legMode == PartnerRouteLegMode.fullTrip,
                              onTap: () {
                                setState(() =>
                                    _legMode = PartnerRouteLegMode.fullTrip);
                                _fetchRoute(force: true, fitCameraAfter: true);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${shipment['trackingId']} • ${_resolvedDestinationTitle(shipment)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_activeRoute != null)
                                  Text(
                                    '${_activeRoute!.formattedDistance} • ${_activeRoute!.formattedDuration} (ETA ${_activeRoute!.etaClockTime})',
                                    style: const TextStyle(
                                      color: Color(0xFF42B883),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  )
                                else
                                  Text(
                                    '${shipment['distanceKm'] ?? '--'} km • ${shipment['shipmentStatus'] ?? 'Active'}',
                                    style: const TextStyle(
                                      color: Color(0xFFF99A4F),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_activeRoute != null &&
                              _activeRoute!.steps.isNotEmpty)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFF99A4F),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: _showTurnByTurnSheet,
                              icon: const Icon(Icons.directions_rounded,
                                  size: 18),
                              label: const Text(
                                'Steps',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 10, color: Color(0xFF42B883)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              shipment['pickupLocation']?['formattedAddress'] ??
                                  '',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 13, color: Color(0xFFE53935)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              shipment['deliveryLocation']
                                      ?['formattedAddress'] ??
                                  '',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => widget.onOpenChat(shipment),
                              icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 17),
                              label: const Text('Chat'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF99A4F),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                final id = shipment['_id']?.toString() ?? '';
                                final st =
                                    shipment['shipmentStatus']?.toString() ??
                                        '';
                                if (id.isNotEmpty) {
                                  widget.onAdvanceStatus(
                                      id, _nextStatusValue(st));
                                }
                              },
                              child: Text(
                                _nextStatusLabel(
                                  shipment['shipmentStatus']?.toString() ?? '',
                                ),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _LegChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LegChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF99A4F) : const Color(0xFF282C37),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MapActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const _MapActionBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF99A4F) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: active ? Colors.white : const Color(0xFF1A1D24),
          size: 20,
        ),
      ),
    );
  }
}
