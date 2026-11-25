import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const ProviderScope(child: SwiftRouteAdminApp()));
}

class SwiftRouteAdminApp extends StatelessWidget {
  const SwiftRouteAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftRoute Admin Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F3F3),
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF99A4F)),
      ),
      home: const AdminDashboardWeb(),
    );
  }
}

class AdminDashboardWeb extends StatefulWidget {
  const AdminDashboardWeb({super.key});

  @override
  State<AdminDashboardWeb> createState() => _AdminDashboardWebState();
}

class _AdminDashboardWebState extends State<AdminDashboardWeb> {
  final _dio = Dio(BaseOptions(baseUrl: 'http://localhost:5000/api'));
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    try {
      final res = await _dio.get('/admin/dashboard');
      if (mounted) setState(() => _stats = res.data['stats'] ?? {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final kpis = [
      {'label': 'Total Revenue', 'value': '₹${_stats['totalRevenue'] ?? 0}', 'icon': Icons.payments_rounded},
      {'label': 'Total Shipments', 'value': '${_stats['totalShipments'] ?? 0}', 'icon': Icons.inventory_2_rounded},
      {'label': 'Active / Pending', 'value': '${_stats['pendingShipments'] ?? 0}', 'icon': Icons.local_shipping_rounded},
      {'label': 'Completed', 'value': '${_stats['completedShipments'] ?? 0}', 'icon': Icons.check_circle_rounded},
      {'label': 'Customers', 'value': '${_stats['totalCustomers'] ?? 0}', 'icon': Icons.people_alt_rounded},
      {'label': 'Fleet Partners', 'value': '${_stats['totalAgents'] ?? 0}', 'icon': Icons.two_wheeler_rounded},
    ];

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 240,
            color: const Color(0xFF242424),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SwiftRoute Admin',
                    style: TextStyle(color: Color(0xFFF99A4F), fontWeight: FontWeight.w700, fontSize: 20)),
                const SizedBox(height: 36),
                for (final nav in ['Overview', 'Shipments', 'Fleet Partners', 'Customers', 'Promotions', 'Payments'])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(nav, style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Operations Overview', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  GridView.builder(
                    shrinkWrap: true,
                    itemCount: kpis.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                      childAspectRatio: 2.3,
                    ),
                    itemBuilder: (context, index) {
                      final kpi = kpis[index];
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9EDE8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(kpi['icon'] as IconData, color: const Color(0xFFF99A4F), size: 28),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(kpi['label'] as String, style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                                Text(kpi['value'] as String,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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
