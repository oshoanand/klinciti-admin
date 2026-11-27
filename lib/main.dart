import 'dart:async';
import 'dart:developer';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overlay_support/overlay_support.dart';

// Core Imports
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/date_formatter.dart';
import 'shared/widgets/global_network_wrapper.dart';

// Feature Imports
import 'features/auth/providers/auth_provider.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // 1. Ensure Flutter bindings are initialized before native/plugin calls
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Capture uncaught framework & platform errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      log(
        'FlutterError: ${details.exceptionAsString()}',
        stackTrace: details.stack,
        name: 'Main',
      );
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (kDebugMode) {
      log('Uncaught async error: $error', stackTrace: stack, name: 'Main');
    }
    return true;
  };

  // 3. Initialize Firebase & register background FCM handler immediately
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 4. Initialize Russian locale date formatting (Intl)
  try {
    await DateFormatter.initialize();
  } catch (e) {
    log('DateFormatter init failed: $e', name: 'Main');
  }

  // 5. Create top-level ProviderContainer & pre-load persisted auth state
  final container = ProviderContainer();
  try {
    await container.read(authControllerProvider).checkInitialAuth();
  } catch (e) {
    log('Initial auth check failed: $e', name: 'Main');
  }

  // 6. Render UI immediately (never block splash screen on FCM permissions/network)
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KlincitiAdminApp(),
    ),
  );
}

class KlincitiAdminApp extends ConsumerStatefulWidget {
  const KlincitiAdminApp({super.key});

  @override
  ConsumerState<KlincitiAdminApp> createState() => _KlincitiAdminAppState();
}

class _KlincitiAdminAppState extends ConsumerState<KlincitiAdminApp> {
  @override
  void initState() {
    super.initState();
    // Initialize FCM & local notifications once the navigator tree is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref.read(notificationServiceProvider).initialize().catchError((
          Object e,
        ) {
          log('NotificationService init failed: $e', name: 'Main');
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return OverlaySupport.global(
      child: MaterialApp.router(
        title: 'Klinciti Admin',
        debugShowCheckedModeBanner: false,

        builder: (context, child) {
          return GlobalNetworkWrapper(child: child ?? const SizedBox.shrink());
        },

        // ==========================================
        // THEMING
        // ==========================================
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        // Keep light mode until all admin screens use Theme.of(context).colorScheme
        themeMode: ThemeMode.light,

        // ==========================================
        // LOCALIZATION (ru_RU)
        // ==========================================
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
        locale: const Locale('ru', 'RU'),

        // ==========================================
        // ROUTING
        // ==========================================
        routerConfig: router,
      ),
    );
  }
}
