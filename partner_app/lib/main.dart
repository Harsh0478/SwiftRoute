import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'core/services/fast_location_service.dart';
import 'features/chat/partner_chat_screen.dart';
import 'features/map/partner_route_map_screen.dart';

// ============================================================
// CONFIGURATION
// ============================================================

const String mapboxPublicToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
);

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5000/api',
);

const String socketBaseUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://10.0.2.2:5000',
);

const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
);

Dio _createDio() {
  return Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );
}

// ============================================================
// MAIN
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    mapboxPublicToken.isNotEmpty,
    'MAPBOX_ACCESS_TOKEN is empty. Run with --dart-define-from-file=.env',
  );
  mapbox.MapboxOptions.setAccessToken(mapboxPublicToken);

  runApp(const ProviderScope(child: PartnerApp()));
}

// ============================================================
// APP
// ============================================================

class PartnerApp extends StatelessWidget {
  const PartnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftRoute Partner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F3F3),
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF99A4F),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const _PartnerAuthGate(),
    );
  }
}

// ============================================================
// AUTH GATE
// ============================================================

class _PartnerAuthGate extends StatefulWidget {
  const _PartnerAuthGate();

  @override
  State<_PartnerAuthGate> createState() => _PartnerAuthGateState();
}

class _PartnerAuthGateState extends State<_PartnerAuthGate> {
  bool _checking = true;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final token = await _secureStorage.read(key: 'agent_token');
    if (!mounted) return;
    setState(() {
      _authenticated = token != null && token.isNotEmpty;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_authenticated) {
      return PartnerAuthScreen(
        onAuthenticated: () {
          setState(() => _authenticated = true);
        },
      );
    }

    return PartnerDashboardScreen(
      onLogout: () async {
        await _secureStorage.delete(key: 'agent_token');
        if (!mounted) return;
        setState(() => _authenticated = false);
      },
    );
  }
}

// ============================================================
// PARTNER LOGIN & REGISTRATION SCREEN
// ============================================================

class PartnerAuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const PartnerAuthScreen({super.key, required this.onAuthenticated});

  @override
  State<PartnerAuthScreen> createState() => _PartnerAuthScreenState();
}

class _PartnerAuthScreenState extends State<PartnerAuthScreen> {
  final Dio _dio = _createDio();
  bool _isRegister = false;
  bool _submitting = false;
  bool _obscurePassword = true;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _vehicleNumberCtrl = TextEditingController();
  final _licenseNumberCtrl = TextEditingController();
  String _vehicleType = 'bike';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    _licenseNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter email and password.');
      return;
    }

    if (_isRegister &&
        (_nameCtrl.text.trim().isEmpty ||
            _phoneCtrl.text.trim().isEmpty ||
            _vehicleNumberCtrl.text.trim().isEmpty ||
            _licenseNumberCtrl.text.trim().isEmpty)) {
      _showMessage('Please fill in all partner registration details.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final Response<dynamic> response;
      if (_isRegister) {
        response = await _dio.post(
          '/agents/register',
          data: {
            'name': _nameCtrl.text.trim(),
            'email': email,
            'phone': _phoneCtrl.text.trim(),
            'password': password,
            'vehicleType': _vehicleType,
            'vehicleNumber': _vehicleNumberCtrl.text.trim().toUpperCase(),
            'licenseNumber': _licenseNumberCtrl.text.trim(),
          },
        );
      } else {
        response = await _dio.post(
          '/agents/login',
          data: {
            'email': email,
            'password': password,
          },
        );
      }

      final token = response.data['accessToken']?.toString();
      if (token == null || token.isEmpty) {
        _showMessage('Authentication token missing from server response.');
        return;
      }

      await _secureStorage.write(key: 'agent_token', value: token);
      if (!mounted) return;
      widget.onAuthenticated();
    } on DioException catch (e) {
      _showMessage(
        e.response?.data?['message'] ??
            'Connection failed. Ensure backend is running on $apiBaseUrl',
      );
    } catch (e) {
      _showMessage('Authentication failed: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.delivery_dining_rounded,
                    size: 54,
                    color: Color(0xFFF99A4F),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRegister ? 'Partner Registration' : 'Courier Partner Login',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegister
                        ? 'Create a delivery partner account to accept shipments.'
                        : 'Sign in with your delivery partner credentials.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  if (_isRegister) ...[
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: '+919876543210',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                  ),
                  if (_isRegister) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        prefixIcon: Icon(Icons.two_wheeler_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'bike', child: Text('Bike')),
                        DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
                        DropdownMenuItem(value: 'van', child: Text('Van')),
                        DropdownMenuItem(value: 'truck', child: Text('Truck')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _vehicleType = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _vehicleNumberCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Number',
                        hintText: 'MH26AB1234',
                        prefixIcon: Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _licenseNumberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Driving License Number',
                        hintText: 'MH2620230012345',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF99A4F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isRegister ? 'Register & Continue' : 'Login',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            setState(() => _isRegister = !_isRegister);
                          },
                    child: Text(
                      _isRegister
                          ? 'Already have a partner account? Login'
                          : 'New courier partner? Register here',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PARTNER DASHBOARD & MULTI-TAB WORKSPACE
// ============================================================

class PartnerDashboardScreen extends ConsumerStatefulWidget {
  final Future<void> Function()? onLogout;

  const PartnerDashboardScreen({super.key, this.onLogout});

  @override
  ConsumerState<PartnerDashboardScreen> createState() =>
      _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState
    extends ConsumerState<PartnerDashboardScreen> {
  final Dio _dio = _createDio();
  final ImagePicker _imagePicker = ImagePicker();
  io.Socket? _socket;

  int _navIndex = 0;
  bool _isOnline = false;
  bool _isLoading = true;
  bool _isUpdatingAvailability = false;
  bool _isBroadcastingGps = false;
  String? _uploadingProofShipmentId;

  String? _errorMessage;
  geo.Position? _currentPosition;
  DateTime? _lastLocationSyncedAt;

  StreamSubscription<geo.Position>? _positionSub;
  Timer? _heartbeatTimer;

  Map<String, dynamic>? _agentProfile;
  List<dynamic> _assignments = [];
  final Map<String, int> _unreadChatCounts = {};
  String? _activeChatShipmentId;
  String? _mapFocusedShipmentId;

  @override
  void initState() {
    super.initState();
    _initPartnerSession();
  }

  Future<void> _initPartnerSession() async {
    await Future.wait([
      _loadAssignments(),
      _loadAgentProfile(),
    ]);
    await _syncInitialLocationAndAvailability();
  }

  Future<void> _loadAgentProfile() async {
    try {
      final token = await _secureStorage.read(key: 'agent_token');
      if (token == null || token.isEmpty) return;
      _dio.options.headers['Authorization'] = 'Bearer $token';

      final res = await _dio.get('/agents/profile');
      if (!mounted) return;
      setState(() {
        _agentProfile = Map<String, dynamic>.from(res.data['agent'] ?? {});
      });
    } catch (e) {
      debugPrint('Profile load warning: $e');
    }
  }

  Future<void> _syncInitialLocationAndAvailability() async {
    final token = await _secureStorage.read(key: 'agent_token');
    if (token == null || token.isEmpty) return;

    _dio.options.headers['Authorization'] = 'Bearer $token';

    final hasPermission = await _checkLocationPermission(silent: true);
    if (!hasPermission) return;

    // 1. Use instant cached/last-known GPS fix (<50ms) so going online never stalls
    final instantPos = await FastLocationService.getInstantPosition();
    final initialPos = instantPos ?? await _acquireCurrentPosition();
    if (initialPos == null || !mounted) return;

    setState(() {
      _currentPosition = initialPos;
      _lastLocationSyncedAt = DateTime.now();
    });

    try {
      final profileRes = await _dio.get('/agents/profile');
      final agentMap = Map<String, dynamic>.from(profileRes.data['agent'] ?? {});
      final serverOnline = agentMap['isOnline'] == true;

      await _dio.put(
        '/agents/availability',
        data: {
          'isOnline': true,
          'lat': initialPos.latitude,
          'lng': initialPos.longitude,
        },
      );

      await _connectSocket();
      _joinAllAssignmentRooms();
      _startLocationTracking();
      _startHeartbeatTimer();

      if (!mounted) return;
      setState(() {
        _agentProfile = agentMap;
        _isOnline = true;
      });

      if (!serverOnline) {
        await _loadAssignments();
      }

      // 2. Refine with a fresh fast GPS fix in the background if we used cached coordinates
      if (instantPos != null) {
        unawaited(() async {
          final freshPos = await FastLocationService.getFastPosition(
            timeout: const Duration(seconds: 4),
          );
          if (freshPos != null && mounted && _isOnline) {
            setState(() {
              _currentPosition = freshPos;
              _lastLocationSyncedAt = DateTime.now();
            });
            await _sendLocation(freshPos);
          }
        }());
      }
    } catch (e) {
      debugPrint('Initial location sync warning: $e');
    }
  }

  Future<geo.Position?> _acquireCurrentPosition() async {
    return await FastLocationService.getFastPosition(
      timeout: const Duration(seconds: 4),
    );
  }

  Future<void> _loadAssignments() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final token = await _secureStorage.read(key: 'agent_token');

      if (token == null || token.isEmpty) {
        if (widget.onLogout != null) {
          await widget.onLogout!();
          return;
        }
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please login to continue.';
        });
        return;
      }

      _dio.options.headers['Authorization'] = 'Bearer $token';

      final response = await _dio.get('/agents/assignments');

      if (!mounted) return;

      setState(() {
        _assignments = response.data['shipments'] ?? [];
        _isLoading = false;
      });

      _joinAllAssignmentRooms();
      await _refreshUnreadCounts();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && widget.onLogout != null) {
        await widget.onLogout!();
        return;
      }
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            e.response?.data?['message'] ?? 'Failed to load assignments.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong.';
      });
    }
  }

  void _joinAllAssignmentRooms() {
    if (_socket == null || !_socket!.connected) return;
    for (final shipment in _assignments) {
      final id = shipment['_id']?.toString();
      if (id != null && id.isNotEmpty) {
        _socket!.emit('shipment:join', {'shipmentId': id});
      }
    }
  }

  Future<void> _refreshUnreadCounts() async {
    for (final shipment in _assignments) {
      final id = shipment['_id']?.toString();
      if (id == null || id.isEmpty) continue;
      try {
        final res = await _dio.get('/chat/$id/messages');
        final msgs = List<dynamic>.from(res.data['messages'] ?? []);
        final unread = msgs
            .where((m) => m['senderRole'] != 'agent' && m['isRead'] != true)
            .length;
        if (mounted) {
          setState(() => _unreadChatCounts[id] = unread);
        }
      } catch (_) {}
    }
  }

  Future<bool> _checkLocationPermission({bool silent = false}) async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted || silent) return false;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text(
            'Please enable GPS location services to share your live location with customers.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await geo.Geolocator.openLocationSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      return false;
    }

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();

    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      if (!mounted || silent) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to go online.'),
        ),
      );

      return false;
    }

    return true;
  }

  Future<void> _toggleOnline(bool value) async {
    if (_isUpdatingAvailability) return;

    setState(() => _isUpdatingAvailability = true);

    try {
      // Going offline should never block on waiting for a new GPS lock
      if (!value) {
        final knownPos =
            _currentPosition ?? await FastLocationService.getInstantPosition();
        await _dio.put(
          '/agents/availability',
          data: {
            'isOnline': false,
            if (knownPos != null) 'lat': knownPos.latitude,
            if (knownPos != null) 'lng': knownPos.longitude,
          },
        );

        _stopHeartbeatTimer();
        await _stopLocationTracking();
        _disconnectSocket();

        if (!mounted) return;
        setState(() {
          _isOnline = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are now offline.')),
        );
        return;
      }

      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      // 1. Use instant cached/last-known position (<50ms) or fast 4s GPS lock
      final instantPos =
          _currentPosition ?? await FastLocationService.getInstantPosition();
      final geo.Position? position = instantPos ?? await _acquireCurrentPosition();
      if (position == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to read GPS location. Try again.'),
          ),
        );
        return;
      }

      final res = await _dio.put(
        '/agents/availability',
        data: {
          'isOnline': true,
          'lat': position.latitude,
          'lng': position.longitude,
        },
      );

      await _connectSocket();
      _joinAllAssignmentRooms();
      _startLocationTracking();
      _startHeartbeatTimer();
      await _loadAssignments();

      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _lastLocationSyncedAt = DateTime.now();
        _isOnline = true;
      });

      final claimed = res.data?['claimedCount'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimed > 0
                ? 'You are online! $claimed pending order(s) assigned.'
                : 'You are now online and sharing live GPS.',
          ),
        ),
      );

      // 2. Refine with a fresh GPS fix in the background without blocking toggle
      if (instantPos != null) {
        unawaited(() async {
          final freshPos = await FastLocationService.getFastPosition(
            timeout: const Duration(seconds: 4),
          );
          if (freshPos != null && mounted && _isOnline) {
            setState(() {
              _currentPosition = freshPos;
              _lastLocationSyncedAt = DateTime.now();
            });
            await _sendLocation(freshPos);
          }
        }());
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message'] ?? 'Failed to update availability.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  Future<void> _broadcastLocationNow({bool showToast = true}) async {
    if (_isBroadcastingGps) return;
    setState(() => _isBroadcastingGps = true);

    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      // 1. Sync instant cached/last-known position immediately (<50ms)
      final instantPos = await FastLocationService.getInstantPosition();
      if (instantPos != null && mounted) {
        setState(() {
          _currentPosition = instantPos;
          _lastLocationSyncedAt = DateTime.now();
        });
        unawaited(_sendLocation(instantPos));
      }

      // 2. Fetch fresh Wi-Fi/GPS fix with a 4-second timeout
      final freshPos = await FastLocationService.getFastPosition(
        timeout: const Duration(seconds: 4),
      );
      final finalPos = freshPos ?? instantPos;

      if (finalPos == null) {
        if (mounted && showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get current GPS coordinates.')),
          );
        }
        return;
      }

      await _sendLocation(finalPos);
      if (!mounted) return;
      setState(() {
        _currentPosition = finalPos;
        _lastLocationSyncedAt = DateTime.now();
      });

      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location updated: ${finalPos.latitude.toStringAsFixed(4)}, ${finalPos.longitude.toStringAsFixed(4)}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBroadcastingGps = false);
    }
  }

  Future<void> _connectSocket() async {
    final token = await _secureStorage.read(key: 'agent_token');
    if (token == null) return;

    _disconnectSocket();

    _socket = io.io(
      socketBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Partner socket connected: ${_socket?.id}');
      _joinAllAssignmentRooms();
    });

    void handleNewAssignment(dynamic data) {
      _loadAssignments();
      _loadAgentProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New delivery request received! Tap Accept Order to start.'),
          backgroundColor: Color(0xFF42B883),
        ),
      );
    }

    _socket!.on('agent:new_assignment', handleNewAssignment);
    _socket!.on('shipment:assigned', handleNewAssignment);

    _socket!.on('chat:new_message', (dynamic data) {
      if (!mounted || data is! Map) return;
      final senderRole = data['senderRole']?.toString();
      final shipmentId = data['shipmentId']?.toString();
      if (senderRole == 'agent' || shipmentId == null) return;

      if (_activeChatShipmentId == shipmentId) {
        return;
      }

      setState(() {
        _unreadChatCounts[shipmentId] = (_unreadChatCounts[shipmentId] ?? 0) + 1;
      });

      final text = data['text']?.toString() ?? 'New message from customer';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer message: $text'),
          action: SnackBarAction(
            label: 'Reply',
            onPressed: () {
              final match = _assignments.cast<Map<String, dynamic>?>().firstWhere(
                    (s) => s?['_id']?.toString() == shipmentId,
                    orElse: () => null,
                  );
              if (match != null) {
                _openChatScreen(match);
              }
            },
          ),
        ),
      );
    });

    _socket!.connect();
  }

  void _disconnectSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void _startLocationTracking() {
    _positionSub?.cancel();

    _positionSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (geo.Position position) {
        FastLocationService.remember(position);
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _lastLocationSyncedAt = DateTime.now();
          });
        }
        _sendLocation(position);
      },
      onError: (error) {
        debugPrint('GPS stream error: $error');
      },
    );
  }

  Future<void> _sendLocation(geo.Position position) async {
    try {
      await _dio.put(
        '/agents/availability',
        data: {
          'isOnline': _isOnline,
          'lat': position.latitude,
          'lng': position.longitude,
        },
      );
    } catch (_) {}

    if (_socket == null || !_socket!.connected) return;

    for (final shipment in _assignments) {
      final shipmentId = shipment['_id']?.toString();
      if (shipmentId != null && shipmentId.isNotEmpty) {
        _socket!.emit('agent:location_update', {
          'shipmentId': shipmentId,
          'lat': position.latitude,
          'lng': position.longitude,
          'heading': position.heading,
          'speedKmh': position.speed * 3.6,
        });
      }
    }
  }

  Future<void> _stopLocationTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _openChatScreen(Map<String, dynamic> shipment) async {
    final shipmentId = shipment['_id']?.toString() ?? '';
    if (shipmentId.isEmpty) return;

    final trackingId = shipment['trackingId']?.toString() ?? 'N/A';
    final customerName = shipment['customerId']?['name']?.toString() ??
        shipment['sender']?['name']?.toString() ??
        'Customer';
    final status = shipment['shipmentStatus']?.toString() ?? 'Active';

    setState(() {
      _activeChatShipmentId = shipmentId;
      _unreadChatCounts[shipmentId] = 0;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartnerChatScreen(
          dio: _dio,
          socket: _socket,
          shipmentId: shipmentId,
          trackingId: trackingId,
          customerName: customerName,
          shipmentStatus: status,
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _activeChatShipmentId = null;
        _unreadChatCounts[shipmentId] = 0;
      });
    }
  }

  Future<void> _uploadProofPhoto(String shipmentId, String proofType) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              proofType == 'pickup' ? 'Upload Pickup Proof' : 'Upload Delivery Proof',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFFF99A4F)),
              title: const Text('Take Photo with Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFFF99A4F)),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1400,
      );
      if (picked == null) return;

      setState(() => _uploadingProofShipmentId = shipmentId);

      final formData = FormData.fromMap({
        'proofType': proofType,
        'proofImage': await MultipartFile.fromFile(
          picked.path,
          filename: picked.name,
        ),
      });

      await _dio.post(
        '/agents/shipments/$shipmentId/proof',
        data: formData,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${proofType == 'pickup' ? 'Pickup' : 'Delivery'} photo proof uploaded!',
          ),
        ),
      );
      await _loadAssignments();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message'] ?? 'Failed to upload proof photo.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingProofShipmentId = null);
    }
  }

  Future<void> _respondToOffer(
    String shipmentId, {
    required bool accept,
  }) async {
    try {
      await _dio.put(
        '/agents/shipments/$shipmentId/${accept ? 'accept' : 'decline'}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Order accepted! Tap "Going to Collect Package" when heading to pickup.'
                : 'Order declined and reassigned to the next available partner.',
          ),
          backgroundColor: accept ? const Color(0xFF42B883) : Colors.black87,
        ),
      );
      await Future.wait([
        _loadAssignments(),
        _loadAgentProfile(),
      ]);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message'] ?? 'Unable to respond to order.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong.')),
      );
    }
  }

  Future<void> _advanceStatus(
    String shipmentId,
    String nextStatus,
  ) async {
    if (nextStatus == 'Order Confirmed') {
      await _respondToOffer(shipmentId, accept: true);
      return;
    }

    String? otp;

    if (nextStatus == 'Delivered') {
      otp = await _showOtpDialog();
      if (otp == null || otp.isEmpty) return;
    }

    try {
      await _dio.put(
        '/agents/shipments/$shipmentId/status',
        data: {
          'status': nextStatus,
          if (otp != null) 'deliveryOtp': otp,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shipment updated to $nextStatus'),
        ),
      );

      await Future.wait([
        _loadAssignments(),
        _loadAgentProfile(),
      ]);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message'] ?? 'Failed to update shipment status.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong.')),
      );
    }
  }

  Future<String?> _showOtpDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delivery Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ask the customer or receiver for their 4-digit Delivery OTP shown in the Customer App.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Delivery OTP',
                hintText: 'Enter 4-digit PIN',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF99A4F),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final otp = controller.text.trim();
              if (otp.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid 4-digit OTP.')),
                );
                return;
              }
              Navigator.pop(context, otp);
            },
            child: const Text('Verify & Complete'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _refreshAssignments() async {
    await _broadcastLocationNow(showToast: false);
    await Future.wait([
      _loadAssignments(),
      _loadAgentProfile(),
    ]);
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!_isOnline) return;
      final pos = _currentPosition ?? await _acquireCurrentPosition();
      try {
        await _dio.put(
          '/agents/availability',
          data: {
            'isOnline': true,
            if (pos != null) 'lat': pos.latitude,
            if (pos != null) 'lng': pos.longitude,
          },
        );
      } catch (_) {}
      if (_socket != null && _socket!.connected) {
        _socket!.emit('agent:heartbeat', {
          if (pos != null) 'lat': pos.latitude,
          if (pos != null) 'lng': pos.longitude,
        });
      }
    });
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void dispose() {
    _stopHeartbeatTimer();
    _positionSub?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  int get _totalUnreadMessages =>
      _unreadChatCounts.values.fold(0, (sum, count) => sum + count);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _navIndex == 1
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SwiftRoute Partner',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  if (_agentProfile?['name'] != null)
                    Text(
                      '${_agentProfile!['name']} • ${(_agentProfile!['vehicleNumber'] ?? '').toString()}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                ],
              ),
              actions: [
                Row(
                  children: [
                    Text(
                      _isOnline ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _isOnline
                            ? const Color(0xFF42B883)
                            : Colors.grey,
                      ),
                    ),
                    Switch(
                      value: _isOnline,
                      activeThumbColor: const Color(0xFF42B883),
                      onChanged:
                          _isUpdatingAvailability ? null : _toggleOnline,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
              ],
            ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          Column(
            children: [
              _buildLocationBanner(),
              Expanded(child: _buildDeliveriesBody()),
            ],
          ),
          PartnerRouteMapScreen(
            mapboxAccessToken: mapboxPublicToken,
            currentPosition: _currentPosition,
            assignments: _assignments,
            initialShipmentId: _mapFocusedShipmentId,
            isOnline: _isOnline,
            onBroadcastLocationNow: () => _broadcastLocationNow(showToast: true),
            onOpenChat: (shipment) => _openChatScreen(shipment),
            onAdvanceStatus: (id, nextStatus) => _advanceStatus(id, nextStatus),
          ),
          _buildProfileAndEarningsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFF9EDE8),
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _totalUnreadMessages > 0,
              label: Text('$_totalUnreadMessages'),
              child: const Icon(Icons.local_shipping_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _totalUnreadMessages > 0,
              label: Text('$_totalUnreadMessages'),
              child: const Icon(Icons.local_shipping_rounded, color: Color(0xFFF99A4F)),
            ),
            label: 'Deliveries',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded, color: Color(0xFFF99A4F)),
            label: 'Live Map',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: Color(0xFFF99A4F)),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    final hasGps = _currentPosition != null;
    final syncedLabel = _lastLocationSyncedAt != null
        ? ' • Synced ${_lastLocationSyncedAt!.hour.toString().padLeft(2, '0')}:${_lastLocationSyncedAt!.minute.toString().padLeft(2, '0')}'
        : '';
    final label = hasGps
        ? 'GPS: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}$syncedLabel'
        : 'Acquiring current GPS location...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: hasGps ? const Color(0xFFEAF7F1) : const Color(0xFFFFF4E8),
      child: Row(
        children: [
          Icon(
            hasGps ? Icons.my_location : Icons.location_searching,
            size: 16,
            color: hasGps ? const Color(0xFF2E9E6B) : const Color(0xFFF99A4F),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasGps
                    ? const Color(0xFF1F7A50)
                    : const Color(0xFFB86621),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: _isBroadcastingGps
                ? null
                : () => _broadcastLocationNow(showToast: true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                _isBroadcastingGps ? 'Updating...' : 'Update GPS',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF99A4F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveriesBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 50, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAssignments,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_assignments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshAssignments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.62,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isOnline
                            ? Icons.local_shipping_outlined
                            : Icons.power_settings_new,
                        size: 70,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isOnline
                            ? 'No active assignments'
                            : 'You are currently offline',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isOnline
                            ? 'Your live GPS is active. New shipments within 18 km will appear automatically.'
                            : 'Toggle ONLINE in the top bar to receive and auto-claim pickups.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAssignments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _assignments.length,
        itemBuilder: (context, index) {
          final shipment = Map<String, dynamic>.from(_assignments[index]);
          return _buildShipmentCard(shipment);
        },
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

  int _statusStepIndex(String status) {
    switch (status) {
      case 'Assigning Courier...':
        return -1;
      case 'Order Confirmed':
        return 0;
      case 'Going to Collect Package':
        return 1;
      case 'Package Picked Up':
        return 2;
      case 'Processing at Facility':
      case 'In Transit':
      case 'Out for Delivery':
        return 3;
      case 'Delivered':
        return 4;
      default:
        return 0;
    }
  }

  Widget _buildShipmentCard(Map<String, dynamic> shipment) {
    final trackingId = shipment['trackingId']?.toString() ?? 'N/A';
    final status = shipment['shipmentStatus']?.toString() ?? 'Order Confirmed';
    final shipmentId = shipment['_id']?.toString() ?? '';

    final pickupAddress =
        shipment['pickupLocation']?['formattedAddress']?.toString() ??
            'Pickup address unavailable';
    final deliveryAddress =
        shipment['deliveryLocation']?['formattedAddress']?.toString() ??
            'Delivery address unavailable';

    final sender = shipment['sender'] as Map<String, dynamic>? ?? {};
    final receiver = shipment['receiver'] as Map<String, dynamic>? ?? {};
    final pkg = shipment['packageDetails'] as Map<String, dynamic>? ?? {};
    final paymentMethod = shipment['paymentMethod']?.toString() ?? 'online';
    final shippingCost = shipment['shippingCost'] ?? 0;
    final distanceKm = shipment['distanceKm'] ?? 0;
    final unreadCount = _unreadChatCounts[shipmentId] ?? 0;
    final currentStep = _statusStepIndex(status);
    final isUploadingProof = _uploadingProofShipmentId == shipmentId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ID: $trackingId',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${pkg['name'] ?? 'Parcel'} • ${pkg['weightKg'] ?? 1} kg • $distanceKm km',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EDE8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFFF99A4F),
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(4, (i) {
              final active = i <= currentStep;
              return Expanded(
                flex: i == 3 ? 0 : 1,
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: active ? const Color(0xFFF99A4F) : Colors.black26,
                    ),
                    if (i < 3)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: i < currentStep
                              ? const Color(0xFFF99A4F)
                              : Colors.black12,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: paymentMethod == 'cod'
                      ? const Color(0xFFFFF4E8)
                      : const Color(0xFFEAF7F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  paymentMethod == 'cod'
                      ? 'Collect Cash (COD): ₹$shippingCost'
                      : 'Prepaid Online • Earn ₹${((shippingCost as num) * 0.75).round()}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: paymentMethod == 'cod'
                        ? const Color(0xFFB86621)
                        : const Color(0xFF1F7A50),
                  ),
                ),
              ),
              if (pkg['isFragile'] == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'FRAGILE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.circle, size: 11, color: Color(0xFF42B883)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pickup • ${sender['name'] ?? 'Sender'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      pickupAddress,
                      style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                    ),
                    if ((sender['phone'] ?? '').toString().isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: sender['phone'].toString()),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied sender phone: ${sender['phone']}'),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '📞 ${sender['phone']} (tap to copy)',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFF99A4F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.location_on, size: 15, color: Colors.red),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drop-off • ${receiver['name'] ?? 'Receiver'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      deliveryAddress,
                      style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                    ),
                    if ((receiver['phone'] ?? '').toString().isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: receiver['phone'].toString()),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied receiver phone: ${receiver['phone']}'),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '📞 ${receiver['phone']} (tap to copy)',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFF99A4F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: shipmentId.isEmpty
                      ? null
                      : () => _openChatScreen(shipment),
                  icon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text('$unreadCount'),
                    child: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                  ),
                  label: const Text('Chat', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _mapFocusedShipmentId = shipmentId;
                      _navIndex = 1;
                    });
                  },
                  icon: const Icon(Icons.map_outlined, size: 17),
                  label: const Text('Route', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: (shipmentId.isEmpty || isUploadingProof)
                      ? null
                      : () => _uploadProofPhoto(
                            shipmentId,
                            currentStep < 2 ? 'pickup' : 'delivery',
                          ),
                  icon: isUploadingProof
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 17),
                  label: const Text('Proof', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (status == 'Assigning Courier...') ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF99A4F).withValues(alpha: 0.45),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active_rounded,
                      size: 16, color: Color(0xFFF99A4F)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'New delivery request — accept to lock this order or decline to reassign.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9A5218),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: shipmentId.isEmpty
                          ? null
                          : () => _respondToOffer(shipmentId, accept: false),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF42B883),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: shipmentId.isEmpty
                          ? null
                          : () => _respondToOffer(shipmentId, accept: true),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: const Text(
                        'Accept Order',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF99A4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: shipmentId.isEmpty
                    ? null
                    : () =>
                        _advanceStatus(shipmentId, _nextStatusValue(status)),
                child: Text(
                  _nextStatusLabel(status),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileAndEarningsTab() {
    final name = _agentProfile?['name']?.toString() ?? 'Delivery Partner';
    final email = _agentProfile?['email']?.toString() ?? '';
    final phone = _agentProfile?['phone']?.toString() ?? '';
    final vehicleType =
        (_agentProfile?['vehicleType']?.toString() ?? 'bike').toUpperCase();
    final vehicleNumber = _agentProfile?['vehicleNumber']?.toString() ?? 'N/A';
    final licenseNumber = _agentProfile?['licenseNumber']?.toString() ?? 'N/A';
    final totalDeliveries = _agentProfile?['totalDeliveries'] ?? 0;
    final totalEarnings = _agentProfile?['totalEarnings'] ?? 0;
    final rating = _agentProfile?['rating'] ?? 5.0;

    return RefreshIndicator(
      onRefresh: _loadAgentProfile,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D24),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFF99A4F),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'P',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          if (email.isNotEmpty)
                            Text(
                              email,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                              ),
                            ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _StatPill(
                        label: 'Earnings',
                        value: '₹$totalEarnings',
                        accent: const Color(0xFF42B883),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatPill(
                        label: 'Deliveries',
                        value: '$totalDeliveries',
                        accent: const Color(0xFFF99A4F),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatPill(
                        label: 'Rating',
                        value: '$rating ★',
                        accent: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vehicle & Compliance',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 12),
                _DetailRow(label: 'Vehicle Type', value: vehicleType),
                const Divider(height: 20),
                _DetailRow(label: 'Registration No.', value: vehicleNumber),
                const Divider(height: 20),
                _DetailRow(label: 'License Number', value: licenseNumber),
                const Divider(height: 20),
                _DetailRow(
                  label: 'Live GPS Status',
                  value: _currentPosition != null
                      ? '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
                      : 'Not acquired',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _broadcastLocationNow(showToast: true),
              icon: const Icon(Icons.my_location_rounded, color: Color(0xFFF99A4F)),
              label: const Text('Sync Current GPS Location Now'),
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  _stopHeartbeatTimer();
                  try {
                    await _dio.put('/agents/availability', data: {'isOnline': false});
                  } catch (_) {}
                  await _stopLocationTracking();
                  _disconnectSocket();
                  await widget.onLogout!();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Go Offline & Logout',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _StatPill({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF282C37),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ],
    );
  }
}
