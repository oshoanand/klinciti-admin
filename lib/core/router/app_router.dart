import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_names.dart';

// --- Layout ---
import '../../shared/layouts/main_scaffold.dart';

// --- Auth (Dedicated Screens) ---
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
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

// --- Chat Feature ---
import '../../features/chat/presentation/screens/chat_inbox_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';

// --- Support, Staff & Profile ---
import '../../features/support/presentation/support_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';
import '../../features/staff/presentation/staff_list_screen.dart';
import '../../features/staff/presentation/staff_create_screen.dart';
import '../../features/staff/presentation/staff_detail_screen.dart';

// --- Notifications & Categories ---
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/categories/presentation/categories_view.dart';

// ==========================================
// 1. GLOBAL NAVIGATOR KEY
// ==========================================
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Listen to auth changes without destroying the GoRouter instance
  final authNotifier = ValueNotifier<bool>(ref.read(isAuthenticatedProvider));
  ref.onDispose(authNotifier.dispose);

  ref.listen<bool>(isAuthenticatedProvider, (_, next) {
    authNotifier.value = next;
  });

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.login,
    refreshListenable: authNotifier,

    // ==========================================
    // 2. GLOBAL REDIRECT LOGIC
    // ==========================================
    redirect: (context, state) {
      final bool isAuth = ref.read(isAuthenticatedProvider);
      final String location = state.matchedLocation;

      final bool isAuthScreen = location == AppRoutes.login;

      // Not logged in, trying to access a protected route
      if (!isAuth && !isAuthScreen) {
        return AppRoutes.login;
      }

      // Logged in, trying to access auth screens
      if (isAuth && isAuthScreen) {
        return AppRoutes.home;
      }

      return null;
    },

    routes: [
      // ==========================================
      // AUTHENTICATION FLOW
      // ==========================================
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),

      // ==========================================
      // FULL SCREEN PROTECTED ROUTES
      // ==========================================
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.support,
        builder: (context, state) => const SupportScreen(),
      ),

      // --- Staff Management ---
      GoRoute(
        path: AppRoutes.staffList,
        builder: (context, state) => const StaffListScreen(),
      ),
      GoRoute(
        path: AppRoutes.staffCreate,
        builder: (context, state) => const StaffCreateScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.staffDetail}/:id',
        builder: (context, state) {
          final staffId = state.pathParameters['id']!;
          return StaffDetailScreen(staffId: staffId);
        },
      ),

      // --- Dedicated Jobs List (Supports BOTH `/jobs/list?status=X` AND `/jobs/list/X`) ---
      GoRoute(
        path: AppRoutes.jobList, // '/jobs/list'
        builder: (context, state) {
          final status = state.uri.queryParameters['status'];
          return JobListScreen(status: status);
        },
        routes: [
          GoRoute(
            path: ':status', // Matches '/jobs/list/ONGOING'
            builder: (context, state) {
              final status = state.pathParameters['status'];
              return JobListScreen(status: status);
            },
          ),
        ],
      ),

      // --- Job Detail Screen (Supports BOTH `/job/:id` AND `/jobs/detail/:id`) ---
      GoRoute(
        path: '${AppRoutes.jobDetail}/:id', // '/job/:id'
        builder: (context, state) {
          final jobId = state.pathParameters['id']!;
          return JobDetailScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: '${AppRoutes.jobsDetail}/:id', // '/jobs/detail/:id'
        builder: (context, state) {
          final jobId = state.pathParameters['id']!;
          return JobDetailScreen(jobId: jobId);
        },
      ),

      // --- Customer Detail Screen ---
      GoRoute(
        path: '${AppRoutes.customerDetail}/:id',
        builder: (context, state) {
          final customerId = state.pathParameters['id']!;
          return CustomerDetailScreen(customerId: customerId);
        },
      ),

      // --- Workers Sub-Routes ---
      GoRoute(
        path: AppRoutes.workersList, // '/workers/list?authStatus=X&modStatus=Y'
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
        path: '${AppRoutes.workerDetail}/:id', // '/worker/:id'
        builder: (context, state) {
          final workerId = state.pathParameters['id']!;
          return WorkerDetailScreen(workerId: workerId);
        },
      ),

      // --- Notifications ---
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // --- Chat Detail ---
      GoRoute(
        path: '${AppRoutes.chatDetail}/:sessionId/:partnerId',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          final partnerId = state.pathParameters['partnerId']!;
          return ChatDetailScreen(sessionId: sessionId, partnerId: partnerId);
        },
      ),

      // --- Categories ---
      GoRoute(
        path: AppRoutes.categories,
        builder: (context, state) => const CategoriesView(),
      ),

      // ==========================================
      // SHELL ROUTE (With Bottom Nav & Profile Drawer)
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
});
