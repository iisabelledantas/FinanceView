import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/utils/category_format.dart';
import '../../../shared/widgets/async_state_view.dart';
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
        error: (e, _) => AsyncErrorView(
          error: e,
          onRetry: () => ref.invalidate(budgetsProvider),
        ),
        data: (list) {
          _queueBudgetNotifications(list);

          return list.isEmpty
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
                );
        },
      ),
    );
  }

  void _showAddBudgetDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _AddBudgetDialog(),
    );
  }

  void _queueBudgetNotifications(List<dynamic> budgets) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService.instance.notifyMonthlyAnalysisReminder());

      for (final budget in budgets.whereType<Map>()) {
        final category =
            budget['SK']?.toString().replaceAll('BUDGET#', '') ?? '';
        final limit = (budget['monthly_limit'] as num?)?.toDouble() ?? 0;
        final spent = (budget['current_spent'] as num?)?.toDouble() ?? 0;

        unawaited(
          NotificationService.instance.notifyBudgetUsage(
            category: formatCategory(category),
            spent: spent,
            limit: limit,
          ),
        );
      }
    });
  }
}

class _AddBudgetDialog extends ConsumerStatefulWidget {
  const _AddBudgetDialog();

  @override
  ConsumerState<_AddBudgetDialog> createState() => _AddBudgetDialogState();
}

class _AddBudgetDialogState extends ConsumerState<_AddBudgetDialog> {
  static const _categories = [
    'alimentacao',
    'transporte',
    'moradia',
    'saude',
    'educacao',
    'lazer',
    'vestuario',
    'outros',
  ];

  final _formKey = GlobalKey<FormState>();
  final _limitCtrl = TextEditingController();
  String _selected = _categories.first;
  bool _saving = false;

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova meta'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: 'Categoria',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                      _selected = value ?? _selected;
                    }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _limitCtrl,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Limite mensal (R\$)',
              prefixText: 'R\$ ',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final limit = _parseLimit(value ?? '');
              if (limit == null || limit <= 0) {
                return 'Informe um limite maior que zero';
              }
              return null;
            },
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      await ref
          .read(insightsRepositoryProvider)
          .saveBudget(_selected, _parseLimit(_limitCtrl.text)!);

      ref.invalidate(budgetsProvider);
      unawaited(
        NotificationService.instance.notifyBudgetSaved(
          category: formatCategory(_selected),
          limit: _parseLimit(_limitCtrl.text)!,
        ),
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Meta salva com sucesso.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double? _parseLimit(String value) {
    final trimmed = value.trim();
    final normalized = trimmed.contains(',')
        ? trimmed.replaceAll('.', '').replaceAll(',', '.')
        : trimmed;
    return double.tryParse(normalized);
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
            Text(formatCategory(category),
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
