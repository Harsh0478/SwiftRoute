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
    final coords = (geometry['coordinates'] as List<dynamic>?) ?? [77.3210, 19.1383];
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

final mapboxGeocodingProvider = Provider<MapboxGeocodingService>((ref) => MapboxGeocodingService());

class MapboxGeocodingService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.mapbox.com/search/geocode/v6',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<List<MapboxPlace>> searchPlaces(String query, {double? proximityLng, double? proximityLat}) async {
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
          .map((f) => MapboxPlace.fromFeature(Map<String, dynamic>.from(f as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<MapboxPlace?> reverseGeocode({required double latitude, required double longitude}) async {
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
      return MapboxPlace.fromFeature(Map<String, dynamic>.from(features.first as Map));
    } catch (_) {
      return null;
    }
  }

  /// Calculates estimated driving distance (km) and duration (minutes) between two coordinates.
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
    final roadKm = math.max(2.0, double.parse((straightKm * 1.25).toStringAsFixed(1)));
    final durationMin = math.max(15, (roadKm * 2.2).round());
    return (distanceKm: roadKm, durationMinutes: durationMin);
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
