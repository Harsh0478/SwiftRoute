import 'package:dio/dio.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class RouteStepInstruction {
  final String instruction;
  final String streetName;
  final double distanceMeters;
  final double durationSeconds;
  final String maneuverType;
  final String maneuverModifier;

  const RouteStepInstruction({
    required this.instruction,
    required this.streetName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuverType,
    required this.maneuverModifier,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

class PartnerNavigationRoute {
  final List<Position> coordinates;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStepInstruction> steps;
  final String profileUsed;

  const PartnerNavigationRoute({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    required this.profileUsed,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final totalMins = (durationSeconds / 60).round().clamp(1, 9999);
    if (totalMins < 60) {
      return '$totalMins min';
    }
    final hrs = totalMins ~/ 60;
    final mins = totalMins % 60;
    return mins == 0 ? '${hrs}h' : '${hrs}h ${mins}m';
  }

  String get etaClockTime {
    final arrival = DateTime.now().add(Duration(seconds: durationSeconds.round()));
    final hour = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
    final min = arrival.minute.toString().padLeft(2, '0');
    final period = arrival.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }
}

class MapboxDirectionsService {
  final String accessToken;
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.mapbox.com/directions/v5/mapbox',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  MapboxDirectionsService({required this.accessToken});

  /// Fetches a road-snapped turn-by-turn route through [waypoints] (in lng,lat order).
  /// Tries `driving-traffic` first for live congestion ETAs, falling back to `driving`.
  Future<PartnerNavigationRoute?> getRoute({
    required List<Position> waypoints,
  }) async {
    if (accessToken.isEmpty || waypoints.length < 2) return null;

    final coordPath = waypoints
        .map((p) => '${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}')
        .join(';');

    for (final profile in ['driving-traffic', 'driving']) {
      try {
        final res = await _dio.get(
          '/$profile/$coordPath',
          queryParameters: {
            'access_token': accessToken,
            'geometries': 'geojson',
            'overview': 'full',
            'steps': 'true',
            'roundabout_exits': 'true',
          },
        );

        final routes = res.data?['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) continue;

        final primary = Map<String, dynamic>.from(routes.first as Map);
        final geometry = primary['geometry'] as Map<String, dynamic>? ?? {};
        final rawCoords = geometry['coordinates'] as List<dynamic>? ?? [];

        final positions = rawCoords
            .whereType<List>()
            .where((c) => c.length >= 2)
            .map(
              (c) => Position(
                (c[0] as num).toDouble(),
                (c[1] as num).toDouble(),
              ),
            )
            .toList();

        if (positions.length < 2) continue;

        final parsedSteps = <RouteStepInstruction>[];
        final legs = primary['legs'] as List<dynamic>? ?? [];
        for (final rawLeg in legs) {
          if (rawLeg is! Map) continue;
          final steps = rawLeg['steps'] as List<dynamic>? ?? [];
          for (final rawStep in steps) {
            if (rawStep is! Map) continue;
            final maneuver = rawStep['maneuver'] as Map<String, dynamic>? ?? {};
            final instruction = maneuver['instruction']?.toString() ?? '';
            if (instruction.isEmpty) continue;

            parsedSteps.add(
              RouteStepInstruction(
                instruction: instruction,
                streetName: rawStep['name']?.toString() ?? '',
                distanceMeters: (rawStep['distance'] as num? ?? 0).toDouble(),
                durationSeconds: (rawStep['duration'] as num? ?? 0).toDouble(),
                maneuverType: maneuver['type']?.toString() ?? 'turn',
                maneuverModifier: maneuver['modifier']?.toString() ?? 'straight',
              ),
            );
          }
        }

        return PartnerNavigationRoute(
          coordinates: positions,
          distanceMeters: (primary['distance'] as num? ?? 0).toDouble(),
          durationSeconds: (primary['duration'] as num? ?? 0).toDouble(),
          steps: parsedSteps,
          profileUsed: profile,
        );
      } catch (_) {
        // Try fallback profile
      }
    }

    return null;
  }
}
