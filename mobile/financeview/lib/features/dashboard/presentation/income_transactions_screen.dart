import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../shared/utils/category_format.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/insights_repository.dart';

class IncomeTransactionsScreen extends ConsumerWidget {
  const IncomeTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Receitas')),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(insightsProvider),
        ),
        data: (data) {
          final transactions = _parseTransactions(data['income_transactions']);

          if (transactions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payments_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nenhuma receita encontrada'),
                  SizedBox(height: 8),
                  Text('Importe um extrato para visualizar entradas',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final total = transactions.fold<double>(
            0,
            (sum, transaction) => sum + _transactionAmount(transaction).abs(),
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${transactions.length} entradas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                formatter.format(total),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ...transactions.map((transaction) {
                final amount = _transactionAmount(transaction).abs();
                final date = transaction['bookingDate']?.toString() ?? '';
                final description =
                    transaction['description']?.toString() ?? 'Sem descrição';
                final category =
                    transaction['category']?.toString() ?? 'outros';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.arrow_downward, size: 20),
                    ),
                    title: Text(description),
                    subtitle: Text('$date • ${formatCategory(category)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatter.format(amount),
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(
                            context,
                            ref,
                            transaction,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> transaction,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Excluir transação'),
      content: Text(
        'Deseja excluir "${transaction['description'] ?? 'esta transação'}"?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(insightsRepositoryProvider).deleteTransaction(
          transactionId: transaction['transactionId']?.toString() ?? '',
          bookingDate: transaction['bookingDate']?.toString() ?? '',
        );
    ref.invalidate(insightsProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transação excluída')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

List<Map<String, dynamic>> _parseTransactions(dynamic value) {
  if (value is! List) return [];

  return value.whereType<Map>().map((transaction) {
    return transaction.map((key, value) => MapEntry(key.toString(), value));
  }).toList();
}

double _transactionAmount(Map<String, dynamic> transaction) {
  final rawAmount = transaction['rawAmount'];
  if (rawAmount is num) return rawAmount.toDouble();

  final amount = transaction['amount'];
  if (amount is num) return amount.toDouble();

  return double.tryParse(rawAmount?.toString() ?? '') ??
      double.tryParse(amount?.toString() ?? '') ??
      0;
}
