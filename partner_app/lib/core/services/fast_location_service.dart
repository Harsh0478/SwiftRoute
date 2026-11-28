import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Fast two-stage location resolver for Partner App:
/// 1. Returns cached/OS last-known GPS fix in <50ms when fresh (within 5 minutes).
/// 2. Requests a Wi-Fi/cell + GPS fix with [LocationAccuracy.medium] and a short
///    timeout so indoor devices never stall for 8+ seconds when going online or
///    tapping Update GPS.
class FastLocationService {
  static Position? _memoryCachedPosition;
  static DateTime? _memoryCachedAt;

  static Position? get cachedPosition {
    if (_memoryCachedPosition != null &&
        _memoryCachedAt != null &&
        DateTime.now().difference(_memoryCachedAt!) < const Duration(minutes: 5)) {
      return _memoryCachedPosition;
    }
    return null;
  }

  static void remember(Position pos) {
    _memoryCachedPosition = pos;
    _memoryCachedAt = DateTime.now();
  }

  /// Returns an immediate cached/last-known position if available.
  static Future<Position?> getInstantPosition() async {
    final mem = cachedPosition;
    if (mem != null) return mem;

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        remember(lastKnown);
        return lastKnown;
      }
    } catch (_) {}
    return null;
  }

  /// Resolves a fresh position quickly using balanced/medium accuracy first,
  /// falling back to last-known coordinates if GPS satellites are slow indoors.
  static Future<Position?> getFastPosition({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      );
      remember(pos);
      return pos;
    } catch (_) {
      return await getInstantPosition();
    }
  }
}
