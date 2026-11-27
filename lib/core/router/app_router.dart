import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_names.dart';

// --- Layout ---
import '../../shared/layouts/main_scaffold.dart';

// --- Auth ---
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/providers/auth_provider.dart';

// --- Home & Jobs ---
import '../../features/home/presentation/home_screen.dart';
import '../../features/jobs/presentation/jobs_list_screen.dart';
import '../../features/jobs/presentation/job_detail_screen.dart';

// --- Customers & Workers ---
import '../../features/customers/presentation/customer_list_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/workers/presentation/workers_dashboard_screen.dart';
import '../../features/workers/presentation/workers_list_screen.dart';
import '../../features/workers/presentation/worker_detail_screen.dart';

// --- Chat & Broadcast ---
import '../../features/chat/presentation/screens/chat_inbox_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';
import '../../features/chat/presentation/screens/admin_broadcast_screen.dart';

// --- Support, Staff & Profile ---
import '../../features/support/presentation/support_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';
import '../../features/staff/presentation/staff_list_screen.dart';
import '../../features/staff/presentation/staff_create_screen.dart';
import '../../features/staff/presentation/staff_detail_screen.dart';

// --- Notifications & Categories ---
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/categories/presentation/categories_view.dart';

// --- Finance & Cash Control ---
import '../../features/finance/presentation/finance_screen.dart';
import '../../features/cash_control/presentation/admin_cash_monitor_screen.dart';
import '../../features/cash_control/presentation/admin_cash_settings_screen.dart';

// ==========================================
// 1. GLOBAL NAVIGATOR KEY
// ==========================================
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

const _adminOnlyPrefixes = <String>[
  AppRoutes.cashSettings,
  AppRoutes.finance,
  AppRoutes.staffList,
  AppRoutes.staffCreate,
  AppRoutes.staffDetail,
  '/admin/broadcast',
];

ChatDetailScreen _buildChatDetailScreen(GoRouterState state) {
  final sessionId = state.pathParameters['sessionId'] ?? '';
  final partnerId =
      state.pathParameters['partnerId'] ??
      state.uri.queryParameters['partnerId'] ??
      '';

  String? partnerName = state.uri.queryParameters['partnerName'];
  String? partnerAvatar = state.uri.queryParameters['partnerAvatar'];

  if (state.extra is Map) {
    final extra = Map<String, dynamic>.from(state.extra as Map);
    partnerName ??= extra['partnerName']?.toString();
    partnerAvatar ??= extra['partnerAvatar']?.toString();
  }

  return ChatDetailScreen(
    sessionId: sessionId,
    partnerId: partnerId,
    partnerName: partnerName,
    partnerAvatar: partnerAvatar,
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  // Listen to auth changes without recreating the GoRouter instance
  final authNotifier = ValueNotifier<bool>(ref.read(isAuthenticatedProvider));

  ref.listen<bool>(isAuthenticatedProvider, (_, next) {
    authNotifier.value = next;
  });

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.login,
    refreshListenable: authNotifier,

    // ==========================================
    // 2. GLOBAL REDIRECT LOGIC (Auth + RBAC + Deep-Link Preservation)
    // ==========================================
    redirect: (context, state) {
      final bool isAuth = ref.read(isAuthenticatedProvider);
      final String location = state.matchedLocation;
      final String fullUri = state.uri.toString();

      final bool isAuthScreen = location == AppRoutes.login;

      // Not logged in -> redirect to login, preserving intended deep link
      if (!isAuth && !isAuthScreen) {
        if (location != '/' &&
            location != AppRoutes.home &&
            location != AppRoutes.profileDummy) {
          final encodedFrom = Uri.encodeComponent(fullUri);
          return '${AppRoutes.login}?from=$encodedFrom';
        }
        return AppRoutes.login;
      }

      // Logged in on login screen -> restore preserved deep link or go Home
      if (isAuth && isAuthScreen) {
        final from = state.uri.queryParameters['from'];
        if (from != null &&
            from.startsWith('/') &&
            !from.startsWith('//') &&
            !from.startsWith(AppRoutes.login) &&
            !from.startsWith(AppRoutes.profileDummy)) {
          return from;
        }
        return AppRoutes.home;
      }

      // Root, dummy drawer branch & legacy dashboard aliases
      if (location == '/' ||
          location == AppRoutes.jobDashboard ||
          location == AppRoutes.profileDummy) {
        return isAuth ? AppRoutes.home : AppRoutes.login;
      }

      // Guard ADMINISTRATOR-only routes from SUPPORT accounts
      if (isAuth) {
        final role = (ref.read(currentUserProvider)?['role'] ?? '')
            .toString()
            .toUpperCase();
        if (role == 'SUPPORT' &&
            _adminOnlyPrefixes.any((prefix) => location.startsWith(prefix))) {
          return AppRoutes.home;
        }
      }

      return null;
    },

    // ==========================================
    // 3. FALLBACK ERROR SCREEN
    // ==========================================
    errorBuilder: (context, state) => _RouteNotFoundScreen(
      uri: state.uri.toString(),
      isAuthenticated: ref.read(isAuthenticatedProvider),
    ),

    routes: [
      // ==========================================
      // AUTHENTICATION FLOW
      // ==========================================
      GoRoute(
        path: AppRoutes.login,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),

      // ==========================================
      // FULL-SCREEN PROTECTED ROUTES
      // ==========================================
      GoRoute(
        path: AppRoutes.profileEdit,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.support,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SupportScreen(),
      ),

      // --- Finance & Cash Control ---
      GoRoute(
        path: AppRoutes.finance,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return FinanceScreen(initialTab: tab);
        },
      ),
      GoRoute(
        path: AppRoutes.cashMonitor,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdminCashMonitorScreen(),
      ),
      GoRoute(
        path: AppRoutes.cashSettings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdminCashSettingsScreen(),
      ),
      GoRoute(
        path: '/admin/broadcast',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdminBroadcastScreen(),
      ),

      // --- Staff Management ---
      GoRoute(
        path: AppRoutes.staffList,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StaffListScreen(),
      ),
      GoRoute(
        path: AppRoutes.staffCreate,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StaffCreateScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.staffDetail}/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final staffId = state.pathParameters['id'] ?? '';
          return StaffDetailScreen(staffId: staffId);
        },
      ),

      // --- Jobs List (Supports BOTH `/jobs/list?status=X` AND `/jobs/list/X`) ---
      GoRoute(
        path: AppRoutes.jobList,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final status = state.uri.queryParameters['status'];
          return JobListScreen(status: status);
        },
        routes: [
          GoRoute(
            path: ':status',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) {
              final status = state.pathParameters['status'];
              return JobListScreen(status: status);
            },
          ),
        ],
      ),

      // --- Job Detail (Supports BOTH `/job/:id` AND `/jobs/detail/:id`) ---
      GoRoute(
        path: '${AppRoutes.jobDetail}/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final jobId = state.pathParameters['id'] ?? '';
          return JobDetailScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: '${AppRoutes.jobsDetail}/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final jobId = state.pathParameters['id'] ?? '';
          return JobDetailScreen(jobId: jobId);
        },
      ),

      // --- Customer Detail ---
      GoRoute(
        path: '${AppRoutes.customerDetail}/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final customerId = state.pathParameters['id'] ?? '';
          return CustomerDetailScreen(customerId: customerId);
        },
      ),

      // --- Workers Sub-Routes ---
      GoRoute(
        path: AppRoutes.workersList,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final authStatus = state.uri.queryParameters['authStatus'];
          final modStatus = state.uri.queryParameters['modStatus'];
          return WorkersListScreen(
            authStatus: authStatus,
            modStatus: modStatus,
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.workerDetail}/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final workerId = state.pathParameters['id'] ?? '';
          return WorkerDetailScreen(workerId: workerId);
        },
      ),

      // --- Notifications ---
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // --- Chat Detail (Supports BOTH `/chat/:sessionId` AND `/chat/:sessionId/:partnerId`) ---
      GoRoute(
        path: '${AppRoutes.chatDetail}/:sessionId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => _buildChatDetailScreen(state),
        routes: [
          GoRoute(
            path: ':partnerId',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => _buildChatDetailScreen(state),
          ),
        ],
      ),

      // --- Categories ---
      GoRoute(
        path: AppRoutes.categories,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CategoriesView(),
      ),

      // ==========================================
      // SHELL ROUTE (Bottom Nav & Profile Drawer)
      // ==========================================
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.customers,
                builder: (context, state) => const CustomersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.workers,
                builder: (context, state) => const WorkersDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chatList,
                builder: (context, state) => const ChatInboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profileDummy,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    authNotifier.dispose();
  });

  return router;
});

// ==========================================
// 4. FALLBACK SCREEN
// ==========================================
class _RouteNotFoundScreen extends StatelessWidget {
  final String uri;
  final bool isAuthenticated;

  const _RouteNotFoundScreen({
    required this.uri,
    required this.isAuthenticated,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Страница не найдена')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.explore_off_outlined,
                size: 56,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 16),
              const Text(
                'Маршрут не найден',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kDebugMode ? uri : 'Запрошенная страница недоступна.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(
                  isAuthenticated ? AppRoutes.home : AppRoutes.login,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
                child: Text(isAuthenticated ? 'На главную' : 'Ко входу'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
