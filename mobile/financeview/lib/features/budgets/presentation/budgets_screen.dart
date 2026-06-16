import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../dashboard/data/insights_repository.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Metas de orçamento')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddBudgetDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova meta'),
      ),
      body: budgets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('Nenhuma meta cadastrada',
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    const Text('Toque em "Nova meta" para começar'),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, i) => _BudgetCard(budget: list[i]),
              ),
      ),
    );
  }

  void _showAddBudgetDialog(BuildContext context, WidgetRef ref) {
    final categories = [
      'alimentacao',
      'transporte',
      'moradia',
      'saude',
      'educacao',
      'lazer',
      'vestuario',
      'outros',
    ];
    String selected = categories.first;
    final limitCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova meta'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(
                labelText: 'Categoria', border: OutlineInputBorder()),
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => selected = v ?? selected,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: limitCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Limite mensal (R\$)',
              prefixText: 'R\$ ',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final limit =
                  double.tryParse(limitCtrl.text.replaceAll(',', '.')) ?? 0;
              if (limit <= 0) return;
              await ref
                  .read(insightsRepositoryProvider)
                  .saveBudget(selected, limit);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(budgetsProvider);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final dynamic budget;
  const _BudgetCard({required this.budget});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final category = budget['SK']?.toString().replaceAll('BUDGET#', '') ?? '';
    final limit = (budget['monthly_limit'] as num?)?.toDouble() ?? 0;
    final spent = (budget['current_spent'] as num?)?.toDouble() ?? 0;
    final pct = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final color = pct >= 1.0
        ? Colors.red
        : pct >= 0.8
            ? Colors.orange
            : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(category,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(fmt.format(spent),
                style: Theme.of(context).textTheme.bodySmall),
            Text('de ${fmt.format(limit)}',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
      ),
    );
  }
}
