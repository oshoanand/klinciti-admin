import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final jobStatsProvider = FutureProvider.autoDispose((ref) async {
  final api = ref.watch(apiClientProvider);

  try {
    final response = await api.dio.get('/jobs/stats');
    final Map<String, dynamic> rawData = response.data['data'] ?? {};

    final Map<String, int> stats = rawData.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

    return {
      'PENDING': stats['PENDING'] ?? 0,
      'ACCEPTED': stats['ACCEPTED'] ?? 0,
      'ONGOING': stats['ONGOING'] ?? 0,
      'DISPUTED': stats['DISPUTED'] ?? 0,

      'PAYMENT_PENDING': stats['PAYMENT_PENDING'] ?? 0,
      'PAID': stats['PAID'] ?? 0,

      'COMPLETED': stats['COMPLETED'] ?? 0,
      'CANCELLED': stats['CANCELLED'] ?? 0,
      'REFUSED': stats['REFUSED'] ?? 0,
    };
  } catch (e) {
    return {
      'PENDING': 0,
      'ACCEPTED': 0,
      'ONGOING': 0,
      'DISPUTED': 0,
      'PAYMENT_PENDING': 0,
      'PAID': 0,
      'COMPLETED': 0,
      'CANCELLED': 0,
      'REFUSED': 0,
    };
  }
});
