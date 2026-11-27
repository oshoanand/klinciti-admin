class AppRoutes {
  AppRoutes._();

  // Auth
  static const String login = '/login';

  // Bottom Navigation Tabs
  static const String home = '/home';
  static const String customers = '/customers';
  static const String workers = '/workers';
  static const String chatList = '/chats';
  static const String profileDummy = '/profile';

  // Jobs Routes (Both `jobList` and `jobsList` supported for compatibility)
  static const String jobDashboard = '/dashboard';
  static const String jobList = '/jobs/list';
  static const String jobsList = '/jobs/list';
  static const String jobDetail = '/job';
  static const String jobsDetail = '/jobs/detail';

  // Finance Routes
  static const String finance = '/finance';

  // Chat Routes
  static const String chatDetail = '/chat';

  // Profile, Support & Notifications
  static const String support = '/support';
  static const String notifications = '/notifications';
  static const String profileEdit = '/profile/edit';

  // Staff Routes
  static const String staffList = '/staffs';
  static const String staffCreate = '/staff/new';
  static const String staffEdit = '/staff/edit';
  static const String staffDetail = '/staff/detail';

  // Customers Routes
  static const String customerDetail = '/customers/detail';

  // Workers Routes
  static const String workersList = '/workers/list';
  static const String workerDetail = '/worker';

  // Category Routes
  static const String categories = '/categories';

  static const String cashMonitor = '/admin/cash-monitor';
  static const String cashSettings = '/admin/cash-settings';

  // ==========================================
  // TYPED PATH BUILDERS (Safe Deep-Link Helpers)
  // ==========================================
  static String jobDetailPath(String jobId) => '$jobDetail/$jobId';

  static String workerDetailPath(String workerId) => '$workerDetail/$workerId';

  static String customerDetailPath(String customerId) =>
      '$customerDetail/$customerId';

  static String staffDetailPath(String staffId) => '$staffDetail/$staffId';

  static String chatDetailPath(String sessionId, {String? partnerId}) {
    if (partnerId != null && partnerId.isNotEmpty) {
      return '$chatDetail/$sessionId/$partnerId';
    }
    return '$chatDetail/$sessionId';
  }
}
