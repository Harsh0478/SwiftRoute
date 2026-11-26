import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/dio_client.dart';

const _kDevModeKey = 'development_mode';

final developmentModeProvider =
    StateNotifierProvider<DevelopmentModeNotifier, bool>((ref) {
  return DevelopmentModeNotifier(ref);
});

class DevelopmentModeNotifier extends StateNotifier<bool> {
  final Ref _ref;

  DevelopmentModeNotifier(this._ref) : super(true) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final raw =
          await _ref.read(secureStorageProvider).read(key: _kDevModeKey);
      if (raw != null) {
        state = raw == 'true';
      }
    } catch (_) {
      // Keep default true if secure storage read fails
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      await _ref
          .read(secureStorageProvider)
          .write(key: _kDevModeKey, value: enabled.toString());
    } catch (_) {
      // Ignore storage write failure; in-memory state is already updated
    }
  }
}
