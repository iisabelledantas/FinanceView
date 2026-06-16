import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../dashboard/data/insights_repository.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Transações')),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorView(
          error: e,
          onRetry: () => ref.invalidate(insightsProvider),
        ),
        data: (data) {
          // Extrai transações da evolução mensal (dados que já temos)
          // Em produção, teríamos um endpoint GET /transactions dedicado
          final health = data['health'] as Map<String, dynamic>? ?? {};
          final byCategory =
              health['expenses_by_category'] as Map<String, dynamic>? ?? {};

          if (byCategory.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nenhuma transação encontrada'),
                  SizedBox(height: 8),
                  Text('Importe um extrato para começar',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Resumo por categoria',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...byCategory.entries.map((e) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                          child: Icon(_categoryIcon(e.key), size: 20)),
                      title: Text(e.key,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Text(
                        fmt.format((e.value as num).toDouble()),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  IconData _categoryIcon(String category) => switch (category) {
        'alimentacao' => Icons.restaurant,
        'transporte' => Icons.directions_car,
        'moradia' => Icons.home,
        'saude' => Icons.local_hospital,
        'educacao' => Icons.school,
        'lazer' => Icons.sports_esports,
        'vestuario' => Icons.checkroom,
        'financeiro' => Icons.account_balance,
        'salario' => Icons.payments,
        _ => Icons.category,
      };
}
