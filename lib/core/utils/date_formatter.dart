import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

class DateFormatter {
  static Future<void> initialize() async {
    // Call this in main.dart: await DateFormatter.initialize();
    await initializeDateFormatting('ru_RU', null);
  }

  /// Returns formatting like: "12 октября 2023, 14:30"
  static String formatFullDate(DateTime date) {
    return DateFormat('d MMMM yyyy, HH:mm', 'ru_RU').format(date);
  }

  /// Returns formatting like: "14:30"
  static String formatTime(DateTime date) {
    return DateFormat('HH:mm', 'ru_RU').format(date);
  }

  /// Imitates date-fns formatDistanceToNow (e.g., "5 минут назад", "вчера")
  static String formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 1) {
      return DateFormat('d MMM', 'ru_RU').format(date);
    } else if (difference.inDays == 1) {
      return 'Вчера';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ч. назад';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} мин. назад';
    } else {
      return 'Только что';
    }
  }
}
