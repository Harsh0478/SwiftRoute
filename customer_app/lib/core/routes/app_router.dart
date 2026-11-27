import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/authentication/login_screen.dart';
import '../../features/authentication/register_screen.dart';
import '../../features/home/home_dashboard_screen.dart';
import '../../features/booking/package_booking_wizard.dart';
import '../../features/tracking/live_tracking_screen.dart';
import '../../features/shipments/order_history_screen.dart';
import '../../features/chat/shipment_chat_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/profile_details_screen.dart';
import '../../features/profile/help_support_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeDashboardScreen()),
    GoRoute(path: '/booking', builder: (_, __) => const PackageBookingWizard()),
    GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/profile/details', builder: (_, __) => const ProfileDetailsScreen()),
    GoRoute(path: '/help-support', builder: (_, __) => const HelpSupportScreen()),
    GoRoute(
      path: '/track/:trackingId',
      builder: (_, state) => LiveTrackingScreen(
        trackingId: state.pathParameters['trackingId']!,
        initialShipment: state.extra as Map<String, dynamic>?,
      ),
    ),
    GoRoute(
      path: '/chat/:shipmentId',
      builder: (_, state) => ShipmentChatScreen(shipmentId: state.pathParameters['shipmentId']!),
    ),
  ],
);
