import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../dashboard/data/insights_repository.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(insightsProvider);
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCategory == null
            ? 'Transações'
            : _formatCategory(_selectedCategory!)),
        leading: _selectedCategory == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedCategory = null),
              ),
      ),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorView(
          error: e,
          onRetry: () => ref.invalidate(insightsProvider),
        ),
        data: (data) {
          final health = data['health'] as Map<String, dynamic>? ?? {};
          final byCategory =
              health['expenses_by_category'] as Map<String, dynamic>? ?? {};
          final transactionsByCategory =
              _parseTransactionsByCategory(data['transactions_by_category']);

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

          final selectedCategory = _selectedCategory;
          if (selectedCategory != null) {
            return _CategoryTransactionsView(
              category: selectedCategory,
              transactions: transactionsByCategory[selectedCategory] ?? [],
              formatter: fmt,
              onDelete: (transaction) => _confirmDeleteTransaction(
                context,
                ref,
                transaction,
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
              ...byCategory.entries.map((entry) {
                final count = transactionsByCategory[entry.key]?.length ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                        child: Icon(_categoryIcon(entry.key), size: 20)),
                    title: Text(_formatCategory(entry.key),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('$count transações'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fmt.format((entry.value as num).toDouble()),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => setState(() => _selectedCategory = entry.key),
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

class _CategoryTransactionsView extends StatelessWidget {
  final String category;
  final List<Map<String, dynamic>> transactions;
  final NumberFormat formatter;
  final ValueChanged<Map<String, dynamic>> onDelete;

  const _CategoryTransactionsView({
    required this.category,
    required this.transactions,
    required this.formatter,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(
        child: Text('Nenhuma transação em ${_formatCategory(category)}'),
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
          '${transactions.length} transações',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          formatter.format(total),
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        const SizedBox(height: 16),
        ...transactions.map((transaction) {
          final amount = _transactionAmount(transaction).abs();
          final date = transaction['bookingDate']?.toString() ?? '';
          final description =
              transaction['description']?.toString() ?? 'Sem descrição';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(_categoryIcon(category), size: 20),
              ),
              title: Text(description),
              subtitle: Text(date),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatter.format(amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Excluir',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onDelete(transaction),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

Future<void> _confirmDeleteTransaction(
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

Map<String, List<Map<String, dynamic>>> _parseTransactionsByCategory(
    dynamic value) {
  if (value is! Map) return {};

  return value.map((category, transactions) {
    final items = transactions is List
        ? transactions.whereType<Map>().map((transaction) {
            return transaction.map(
              (key, value) => MapEntry(key.toString(), value),
            );
          }).toList()
        : <Map<String, dynamic>>[];

    return MapEntry(category.toString(), items);
  });
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

String _formatCategory(String category) {
  const labels = {
    'alimentacao': 'Alimentação',
    'transporte': 'Transporte',
    'moradia': 'Moradia',
    'saude': 'Saúde',
    'educacao': 'Educação',
    'lazer': 'Lazer',
    'vestuario': 'Vestuário',
    'financeiro': 'Financeiro',
    'receita': 'Receita',
    'salario': 'Salário',
    'cofrinho_poupanca': 'Cofrinho/Poupança',
    'outros': 'Outros',
  };
  if (labels.containsKey(category)) return labels[category]!;

  return category
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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
      'receita' => Icons.payments,
      'salario' => Icons.payments,
      'cofrinho_poupanca' => Icons.savings,
      _ => Icons.category,
    };
