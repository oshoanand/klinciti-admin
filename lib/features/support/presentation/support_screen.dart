import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/support_provider.dart';
import 'create_ticket_sheet.dart';

// Status styling helper
class StatusConfig {
  final String label;
  final Color textColor;
  final Color bgColor;
  final IconData icon;

  StatusConfig(this.label, this.textColor, this.bgColor, this.icon);
}

StatusConfig _getStatusConfig(String status) {
  switch (status.toUpperCase()) {
    case 'RESOLVED':
    case 'CLOSED':
      return StatusConfig(
        'Решено',
        Colors.green.shade700,
        Colors.green.shade50,
        LucideIcons.circle_check,
      );
    case 'IN_PROGRESS':
      return StatusConfig(
        'В работе',
        Colors.amber.shade700,
        Colors.amber.shade50,
        LucideIcons.clock,
      );
    default:
      return StatusConfig(
        'Открыто',
        const Color(0xFF0F172A),
        const Color(0xFF0F172A).withOpacity(0.1),
        LucideIcons.message_square,
      );
  }
}

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(supportTicketsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Colors.black),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Служба поддержки',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ticketsAsync.when(
        data: (tickets) {
          if (tickets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.info,
                        size: 40,
                        color: Colors.amber.shade500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'У вас нет обращений',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Если у вас возникла проблема или вопрос, создайте новый запрос.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(supportTicketsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16).copyWith(bottom: 100),
              itemCount: tickets.length,
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                final statusConfig = _getStatusConfig(ticket.status);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusConfig.bgColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusConfig.textColor.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  statusConfig.icon,
                                  size: 14,
                                  color: statusConfig.textColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusConfig.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusConfig.textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            DateFormat(
                              'dd.MM.yyyy',
                              'ru_RU',
                            ).format(ticket.createdAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ticket.subject,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ticket.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (err, _) => Center(child: Text('Ошибка загрузки: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateTicketSheet(context),
        backgroundColor: const Color(
          0xFF0F172A,
        ), // Matches your primary bg-primary
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: const Icon(LucideIcons.plus, color: Colors.white, size: 24),
      ),
    );
  }
}
