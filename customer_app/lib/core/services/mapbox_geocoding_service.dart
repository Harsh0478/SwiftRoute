import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';

class MapboxPlace {
  final String name;
  final String fullAddress;
  final String city;
  final String postalCode;
  final double latitude;
  final double longitude;

  const MapboxPlace({
    required this.name,
    required this.fullAddress,
    required this.city,
    required this.postalCode,
    required this.latitude,
    required this.longitude,
  });

  factory MapboxPlace.fromFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
    final coords =
        (geometry['coordinates'] as List<dynamic>?) ?? [77.3210, 19.1383];
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final context = props['context'] as Map<String, dynamic>? ?? {};

    final placeName = props['name']?.toString() ?? 'Selected Location';
    final fullAddr = props['full_address']?.toString() ??
        props['place_formatted']?.toString() ??
        placeName;

    final city = (context['place']?['name'] ??
            context['locality']?['name'] ??
            context['district']?['name'] ??
            context['region']?['name'] ??
            placeName)
        .toString();

    final postcode = (context['postcode']?['name'] ?? '431601').toString();

    return MapboxPlace(
      name: placeName,
      fullAddress: fullAddr,
      city: city,
      postalCode: postcode,
      longitude: (coords[0] as num).toDouble(),
      latitude: (coords[1] as num).toDouble(),
    );
  }
}

class DeliverySpeedOption {
  final String type;
  final String title;
  final String etaLabel;
  final int estimatedMinutes;
  final double averageSpeedKmh;
  final int estimatedTotalInr;
  final bool isAvailable;

  const DeliverySpeedOption({
    required this.type,
    required this.title,
    required this.etaLabel,
    required this.estimatedMinutes,
    required this.averageSpeedKmh,
    required this.estimatedTotalInr,
    required this.isAvailable,
  });
}

final mapboxGeocodingProvider =
    Provider<MapboxGeocodingService>((ref) => MapboxGeocodingService());

class MapboxGeocodingService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.mapbox.com/search/geocode/v6',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<List<MapboxPlace>> searchPlaces(String query,
      {double? proximityLng, double? proximityLat}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];

    try {
      final params = <String, dynamic>{
        'q': trimmed,
        'access_token': ApiConstants.mapboxPublicToken,
        'autocomplete': 'true',
        'country': 'in',
        'worldview': 'in',
        'limit': 5,
      };
      if (proximityLng != null && proximityLat != null) {
        params['proximity'] = '$proximityLng,$proximityLat';
      }

      final res = await _dio.get('/forward', queryParameters: params);
      final features = (res.data['features'] as List<dynamic>?) ?? [];
      return features
          .map((f) =>
              MapboxPlace.fromFeature(Map<String, dynamic>.from(f as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<MapboxPlace?> reverseGeocode(
      {required double latitude, required double longitude}) async {
    try {
      final res = await _dio.get('/reverse', queryParameters: {
        'longitude': longitude,
        'latitude': latitude,
        'access_token': ApiConstants.mapboxPublicToken,
        'worldview': 'in',
        'limit': 1,
      });
      final features = (res.data['features'] as List<dynamic>?) ?? [];
      if (features.isEmpty) return null;
      return MapboxPlace.fromFeature(
          Map<String, dynamic>.from(features.first as Map));
    } catch (_) {
      return null;
    }
  }

  /// Calculates estimated driving distance (km) and base transit duration (minutes) between two coordinates.
  static ({double distanceKm, int durationMinutes}) estimateRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(endLat - startLat);
    final dLng = _degToRad(endLng - startLng);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(startLat)) *
            math.cos(_degToRad(endLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final straightKm = earthRadiusKm * c;

    // Apply 1.25 road-tortuosity factor with a minimum of 2.0 km
    final roadKm =
        math.max(2.0, double.parse((straightKm * 1.25).toStringAsFixed(1)));
    final durationMin = math.max(15, (roadKm * 2.2).round());
    return (distanceKm: roadKm, durationMinutes: durationMin);
  }

  /// Calculates distance-based delivery speeds, ETAs, and fares matching server pricing.
  static List<DeliverySpeedOption> calculateDeliverySpeedOptions({
    required double distanceKm,
    required double weightKg,
    required bool isFragile,
  }) {
    final safeWeight = weightKg > 0 ? weightKg : 1.0;
    final weightSurcharge = safeWeight > 2 ? (safeWeight - 2) * 15 : 0.0;
    final fragileFee = isFragile ? 35.0 : 0.0;

    int computeTotal(int baseRate, int perKm) {
      final baseCharge =
          (baseRate + distanceKm * perKm + weightSurcharge + fragileFee)
              .round();
      final tax = (baseCharge * 0.18).round();
      return baseCharge + tax;
    }

    // 1. Same-Day Priority: ~38 km/h effective speed + 40 min pickup/dispatch buffer (available <= 60 km)
    final sameDayAvailable = distanceKm <= 60.0;
    final sameDayMinutes =
        math.max(45, ((distanceKm / 38.0) * 60 + 40).round());

    // 2. Express Delivery: ~32 km/h intra-city, ~48 km/h highway + handling buffer
    final expressSpeed = distanceKm <= 30 ? 30.0 : 48.0;
    final expressBuffer = distanceKm <= 30 ? 60 : 180;
    final expressMinutes =
        math.max(90, ((distanceKm / expressSpeed) * 60 + expressBuffer).round());

    // 3. Standard Delivery: ~22 km/h intra-city, ~32 km/h intercity + hub sorting buffer
    final standardSpeed = distanceKm <= 30 ? 22.0 : 32.0;
    final standardBuffer = distanceKm <= 30 ? 120 : 480;
    final standardMinutes = math.max(
        150, ((distanceKm / standardSpeed) * 60 + standardBuffer).round());

    return [
      DeliverySpeedOption(
        type: 'same_day',
        title: 'Same-Day Priority',
        etaLabel: sameDayAvailable
            ? formatEta(sameDayMinutes)
            : 'Unavailable (> 60 km)',
        estimatedMinutes: sameDayMinutes,
        averageSpeedKmh: 38.0,
        estimatedTotalInr: computeTotal(120, 14),
        isAvailable: sameDayAvailable,
      ),
      DeliverySpeedOption(
        type: 'express',
        title: 'Express Delivery',
        etaLabel: formatEta(expressMinutes),
        estimatedMinutes: expressMinutes,
        averageSpeedKmh: expressSpeed,
        estimatedTotalInr: computeTotal(75, 11),
        isAvailable: true,
      ),
      DeliverySpeedOption(
        type: 'standard',
        title: 'Standard Delivery',
        etaLabel: formatEta(standardMinutes),
        estimatedMinutes: standardMinutes,
        averageSpeedKmh: standardSpeed,
        estimatedTotalInr: computeTotal(40, 8),
        isAvailable: true,
      ),
    ];
  }

  static String formatEta(int totalMinutes) {
    if (totalMinutes < 60) {
      return '~$totalMinutes mins';
    }
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours < 24) {
      return mins >= 10 ? '~$hours hr $mins mins' : '~$hours hrs';
    }
    final days = hours ~/ 24;
    final remHours = hours % 24;
    if (remHours == 0) {
      return days == 1 ? '~1 day' : '~$days days';
    }
    return days == 1 ? '~1 day $remHours hrs' : '~$days days $remHours hrs';
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
