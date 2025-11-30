import 'package:go_router/go_router.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/profile/credit_history_screen.dart';
import '../../screens/profile/account_settings_screen.dart';
import '../../screens/profile/notification_settings_screen.dart';
import '../../screens/analysis/analysis_screen.dart';
import '../../screens/history/history_screen.dart';
import '../../screens/upload/upload_screen.dart';
import '../../screens/subscription/subscription_screen.dart';
import '../../screens/static/terms_of_service_screen.dart';
import '../../screens/static/privacy_policy_screen.dart';
import '../../screens/static/about_screen.dart';
import '../../screens/static/help_support_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/credit-history',
      builder: (context, state) => const CreditHistoryScreen(),
    ),
    GoRoute(
      path: '/account-settings',
      builder: (context, state) => const AccountSettingsScreen(),
    ),
    GoRoute(
      path: '/notification-settings',
      builder: (context, state) => const NotificationSettingsScreen(),
    ),
    GoRoute(
      path: '/upload',
      builder: (context, state) => const UploadScreen(),
    ),
    GoRoute(
      path: '/analysis/:bulletinId',
      builder: (context, state) {
        final bulletinId = state.pathParameters['bulletinId']!;
        final base64Image = state.extra as String?; // Base64 image from upload (optional)
        return AnalysisScreen(
          bulletinId: bulletinId,
          base64Image: base64Image,
        );
      },
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/subscription',
      builder: (context, state) => const SubscriptionScreen(),
    ),
    
    // Static Pages
    GoRoute(
      path: '/terms',
      builder: (context, state) => const TermsOfServiceScreen(),
    ),
    GoRoute(
      path: '/privacy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: '/help',
      builder: (context, state) => const HelpSupportScreen(),
    ),
  ],
);