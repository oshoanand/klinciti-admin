import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:overlay_support/overlay_support.dart';

// Core Imports
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/notifications/notification_service.dart';
import 'core/utils/date_formatter.dart';
import 'shared/widgets/global_network_wrapper.dart';

// Feature Imports
import 'features/auth/providers/auth_provider.dart';
import 'firebase_options.dart';

void main() async {
  // 1. Ensure Flutter bindings are initialized before calling native code
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Firebase with the generated options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 3. Register FCM Background Handler IMMEDIATELY after Firebase init
  // (firebaseMessagingBackgroundHandler is defined in notification_service.dart)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 4. Initialize Date Formatting for Russian Locale (Intl)
  await DateFormatter.initialize();

  // 5. Create a top-level Riverpod ProviderContainer
  // We do this instead of a standard ProviderScope so we can access
  // asynchronous services BEFORE the UI renders.
  final container = ProviderContainer();

  // 6. Pre-load Auth State
  // This ensures the Bottom Navigation and Profile Drawer instantly know
  // if the user is logged in, preventing UI flickers.
  await container.read(authControllerProvider).checkInitialAuth();

  // 7. Initialize Push Notifications & Local Notification Channels
  final notificationService = container.read(notificationServiceProvider);
  await notificationService.initialize();

  // 8. Run the App
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KlincitiAdminApp(),
    ),
  );
}

class KlincitiAdminApp extends ConsumerWidget {
  const KlincitiAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the GoRouter provider to handle all navigation
    final router = ref.watch(routerProvider);

    // ✅ WRAP WITH OverlaySupport.global to enable in-app drop-down banners
    return OverlaySupport.global(
      child: MaterialApp.router(
        title: 'Klinciti',
        debugShowCheckedModeBanner: false,

        // Wraps the entire app to show "No Internet" banners globally
        builder: (context, child) {
          return GlobalNetworkWrapper(child: child ?? const SizedBox.shrink());
        },

        // ==========================================
        // THEMING
        // ==========================================
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            ThemeMode.system, // Automatically switches based on OS settings
        // ==========================================
        // LOCALIZATION (ru_RU)
        // ==========================================
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ru', 'RU'), // Primary Russian Locale
          Locale('en', 'US'), // Fallback English Locale
        ],
        locale: const Locale('ru', 'RU'), // Force Russian locale by default
        // ==========================================
        // ROUTING
        // ==========================================
        routerConfig: router,
      ),
    );
  }
}
