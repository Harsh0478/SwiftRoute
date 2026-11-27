import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:socket_io_client/socket_io_client.dart' as io;

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
// PARTNER DASHBOARD
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
  // API
  final Dio _dio = _createDio();

  // Socket
  io.Socket? _socket;

  // State
  bool _isOnline = false;
  bool _isLoading = true;
  bool _isUpdatingAvailability = false;

  String? _errorMessage;
  geo.Position? _currentPosition;

  StreamSubscription<geo.Position>? _positionSub;
  Timer? _heartbeatTimer;

  List<dynamic> _assignments = [];

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _initPartnerSession();
  }

  Future<void> _initPartnerSession() async {
    await _loadAssignments();
    await _syncInitialLocationAndAvailability();
  }

  Future<void> _syncInitialLocationAndAvailability() async {
    final token = await _secureStorage.read(key: 'agent_token');
    if (token == null || token.isEmpty) return;

    _dio.options.headers['Authorization'] = 'Bearer $token';

    // Request location permission & acquire current location immediately on launch
    final hasPermission = await _checkLocationPermission(silent: true);
    if (!hasPermission) return;

    final pos = await _acquireCurrentPosition();
    if (pos == null || !mounted) return;

    setState(() {
      _currentPosition = pos;
    });

    try {
      // Check current partner profile status on server
      final profileRes = await _dio.get('/agents/profile');
      final serverOnline = profileRes.data['agent']?['isOnline'] == true;

      // Sync latest GPS coordinates to backend and go online automatically
      await _dio.put(
        '/agents/availability',
        data: {
          'isOnline': true,
          'lat': pos.latitude,
          'lng': pos.longitude,
        },
      );

      await _connectSocket();
      _startLocationTracking();
      _startHeartbeatTimer();

      if (!mounted) return;
      setState(() {
        _isOnline = true;
      });

      if (!serverOnline) {
        await _loadAssignments();
      }
    } catch (e) {
      debugPrint('Initial location sync warning: $e');
    }
  }

  Future<geo.Position?> _acquireCurrentPosition() async {
    try {
      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return await geo.Geolocator.getLastKnownPosition();
    }
  }

  // ==========================================================
  // LOAD ASSIGNMENTS
  // ==========================================================

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

      debugPrint('Assignment API error: ${e.message}');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong.';
      });

      debugPrint('Assignment error: $e');
    }
  }

  // ==========================================================
  // LOCATION PERMISSION
  // ==========================================================

  Future<bool> _checkLocationPermission({bool silent = false}) async {
    bool serviceEnabled =
        await geo.Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted || silent) return false;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text(
            'Please enable location services to share your live location.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await geo.Geolocator.openLocationSettings();
              },
              child: const Text('Settings'),
            ),
          ],
        ),
      );

      return false;
    }

    geo.LocationPermission permission =
        await geo.Geolocator.checkPermission();

    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      if (!mounted || silent) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required.'),
        ),
      );

      return false;
    }

    return true;
  }

  // ==========================================================
  // ONLINE / OFFLINE
  // ==========================================================

  Future<void> _toggleOnline(bool value) async {
    if (_isUpdatingAvailability) return;

    setState(() {
      _isUpdatingAvailability = true;
    });

    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        return;
      }

      final geo.Position? position = await _acquireCurrentPosition();
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
          'isOnline': value,
          'lat': position.latitude,
          'lng': position.longitude,
        },
      );

      if (value) {
        await _connectSocket();
        _startLocationTracking();
        _startHeartbeatTimer();
        await _loadAssignments();
      } else {
        _stopHeartbeatTimer();
        await _stopLocationTracking();
        _disconnectSocket();
      }

      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _isOnline = value;
      });

      final claimed = res.data?['claimedCount'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? (claimed > 0
                    ? 'You are online! $claimed pending order(s) assigned.'
                    : 'You are now online.')
                : 'You are now offline.',
          ),
        ),
      );
    } on DioException catch (e) {
      debugPrint('Availability API error: ${e.message}');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message'] ??
                'Failed to update availability.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Online toggle error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingAvailability = false;
        });
      }
    }
  }

  // ==========================================================
  // SOCKET CONNECTION
  // ==========================================================

  Future<void> _connectSocket() async {
    final token = await _secureStorage.read(key: 'agent_token');

    if (token == null) {
      debugPrint('Socket connection failed: token missing');
      return;
    }

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
      debugPrint('Socket connected: ${_socket?.id}');
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
    });

    _socket!.onConnectError((error) {
      debugPrint('Socket connection error: $error');
    });

    _socket!.onError((error) {
      debugPrint('Socket error: $error');
    });

    // Listen for both event names emitted by server controllers
    void handleNewAssignment(dynamic data) {
      debugPrint('New shipment assigned: $data');
      _loadAssignments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New shipment assigned!'),
        ),
      );
    }

    _socket!.on('agent:new_assignment', handleNewAssignment);
    _socket!.on('shipment:assigned', handleNewAssignment);

    _socket!.connect();
  }

  void _disconnectSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  // ==========================================================
  // GPS TRACKING
  // ==========================================================

  void _startLocationTracking() {
    _positionSub?.cancel();

    _positionSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (geo.Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
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
    // Keep backend agent coordinates updated via REST
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

    if (_socket == null || !_socket!.connected) {
      return;
    }

    // Emit live tracking for every active assignment
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

  // ==========================================================
  // SHIPMENT STATUS
  // ==========================================================

  Future<void> _advanceStatus(
    String shipmentId,
    String nextStatus,
  ) async {
    String? otp;

    if (nextStatus == 'Delivered') {
      otp = await _showOtpDialog();

      if (otp == null || otp.isEmpty) {
        return;
      }
    }

    try {
      await _dio.put(
        '/agents/shipments/$shipmentId/status',
        data: {
          'status': nextStatus,
          'deliveryOtp': otp,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shipment updated to $nextStatus'),
        ),
      );

      await _loadAssignments();
    } on DioException catch (e) {
      debugPrint('Shipment status error: ${e.message}');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message'] ??
                'Failed to update shipment status.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Status update error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong.'),
        ),
      );
    }
  }

  // ==========================================================
  // OTP DIALOG
  // ==========================================================

  Future<String?> _showOtpDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delivery Verification'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Delivery OTP',
            hintText: 'Enter 4-digit OTP',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final otp = controller.text.trim();

              if (otp.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid 4-digit OTP.'),
                  ),
                );

                return;
              }

              Navigator.pop(context, otp);
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    controller.dispose();

    return result;
  }

  // ==========================================================
  // REFRESH
  // ==========================================================

  Future<void> _refreshAssignments() async {
    final pos = await _acquireCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _currentPosition = pos);
      if (_isOnline) {
        await _sendLocation(pos);
      }
    }
    await _loadAssignments();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

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

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Courier Partner',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Row(
            children: [
              Text(
                _isOnline ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _isOnline
                      ? const Color(0xFF42B883)
                      : Colors.grey,
                ),
              ),
              Switch(
                value: _isOnline,
                activeThumbColor: const Color(0xFF42B883),
                onChanged: _isUpdatingAvailability
                    ? null
                    : _toggleOnline,
              ),
            ],
          ),
          if (widget.onLogout != null)
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                _stopHeartbeatTimer();
                try {
                  await _dio.put('/agents/availability', data: {'isOnline': false});
                } catch (_) {}
                await _stopLocationTracking();
                _disconnectSocket();
                await widget.onLogout!();
              },
            ),
          const SizedBox(width: 4),
        ],
      ),

      body: Column(
        children: [
          _buildLocationBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    final hasGps = _currentPosition != null;
    final label = hasGps
        ? 'GPS Active: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
        : 'Acquiring current GPS location...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: hasGps
          ? const Color(0xFFEAF7F1)
          : const Color(0xFFFFF4E8),
      child: Row(
        children: [
          Icon(
            hasGps ? Icons.my_location : Icons.location_searching,
            size: 16,
            color: hasGps
                ? const Color(0xFF2E9E6B)
                : const Color(0xFFF99A4F),
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
            ),
          ),
          InkWell(
            onTap: _refreshAssignments,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Sync',
                style: TextStyle(
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

  // ==========================================================
  // BODY
  // ==========================================================

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 50,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
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
              height: MediaQuery.of(context).size.height * 0.65,
              child: Center(
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
                          ? 'No active assignments.'
                          : 'You are offline.',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isOnline
                          ? 'Waiting for new shipments.'
                          : 'Toggle ONLINE to receive pickups.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
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
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _assignments.length,
        itemBuilder: (context, index) {
          final shipment = _assignments[index];

          return _buildShipmentCard(shipment);
        },
      ),
    );
  }

  // ==========================================================
  // SHIPMENT CARD
  // ==========================================================

  Widget _buildShipmentCard(dynamic shipment) {
    final trackingId = shipment['trackingId'] ?? 'N/A';

    final status = shipment['shipmentStatus'] ?? 'Unknown';

    final pickupAddress =
        shipment['pickupLocation']?['formattedAddress'] ??
            'Pickup address unavailable';

    final deliveryAddress =
        shipment['deliveryLocation']?['formattedAddress'] ??
            'Delivery address unavailable';

    final shipmentId = shipment['_id']?.toString() ?? '';

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
          // Tracking ID and status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'ID: $trackingId',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Chip(
                backgroundColor: const Color(0xFFF9EDE8),
                label: Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFFF99A4F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Pickup
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.circle,
                size: 12,
                color: Colors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pickup',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      pickupAddress,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Delivery
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on,
                size: 16,
                color: Colors.red,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      deliveryAddress,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: shipmentId.isEmpty
                      ? null
                      : () => _advanceStatus(
                            shipmentId,
                            'Out for Delivery',
                          ),
                  child: const Text(
                    'Out for Delivery',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF99A4F),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: shipmentId.isEmpty
                      ? null
                      : () => _advanceStatus(
                            shipmentId,
                            'Delivered',
                          ),
                  child: const Text(
                    'Complete (OTP)',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
