import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/insights_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final market = ref.watch(marketProvider);
    final period = ref.watch(selectedPeriodProvider);
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('FinanceView'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(insightsProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Seletor de período ─────────────────────────
            _PeriodSelector(period: period),
            const SizedBox(height: 16),

            // ── Cards de resumo ────────────────────────────
            insights.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => _ErrorCard(message: e.toString()),
              data: (data) {
                final health = data['health'] as Map<String, dynamic>? ?? {};
                final income =
                    (health['total_income'] as num?)?.toDouble() ?? 0;
                final expenses =
                    (health['total_expenses'] as num?)?.toDouble() ?? 0;
                final savings =
                    (health['savings_rate'] as num?)?.toDouble() ?? 0;
                final byCategory =
                    health['expenses_by_category'] as Map<String, dynamic>? ??
                        {};
                final vsIpca =
                    health['savings_vs_ipca'] as Map<String, dynamic>?;

                return Column(
                  children: [
                    // Cards de receita / despesa / poupança
                    Row(children: [
                      Expanded(
                          child: _SummaryCard(
                              label: 'Receitas',
                              value: fmt.format(income),
                              icon: Icons.arrow_downward,
                              color: Colors.green)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _SummaryCard(
                              label: 'Despesas',
                              value: fmt.format(expenses),
                              icon: Icons.arrow_upward,
                              color: Colors.red)),
                    ]),
                    const SizedBox(height: 8),
                    _SavingsCard(rate: savings, vsIpca: vsIpca),
                    const SizedBox(height: 16),

                    // Gráfico de pizza por categoria
                    if (byCategory.isNotEmpty) ...[
                      const _SectionTitle('Gastos por categoria'),
                      const SizedBox(height: 8),
                      _CategoryPieChart(data: byCategory),
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              },
            ),

            // ── Indicadores de mercado ─────────────────────
            const _SectionTitle('Indicadores de mercado'),
            const SizedBox(height: 8),
            market.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) =>
                  const _ErrorCard(message: 'Indicadores indisponíveis'),
              data: (data) => _MarketCard(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ──────────────────────────────────────

class _PeriodSelector extends ConsumerWidget {
  final String period;
  const _PeriodSelector({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gera os últimos 6 meses
    final months = List.generate(6, (i) {
      final d = DateTime.now();
      final m = DateTime(d.year, d.month - i);
      return '${m.year}-${m.month.toString().padLeft(2, '0')}';
    });

    return DropdownButtonFormField<String>(
      initialValue: period,
      decoration: const InputDecoration(
        labelText: 'Período',
        prefixIcon: Icon(Icons.calendar_month_outlined),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: months
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text(DateFormat('MMMM yyyy', 'pt_BR')
                    .format(DateTime.parse('$m-01'))),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) ref.read(selectedPeriodProvider.notifier).state = v;
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.bold));
}

class _SummaryCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

class _SavingsCard extends StatelessWidget {
  final double rate;
  final Map<String, dynamic>? vsIpca;
  const _SavingsCard({required this.rate, required this.vsIpca});

  @override
  Widget build(BuildContext context) {
    final beating = vsIpca?['beating_inflation'] as bool? ?? false;
    final ipca = (vsIpca?['ipca_monthly_pct'] as num?)?.toDouble() ?? 0;

    return Card(
      color: beating
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(beating ? Icons.trending_up : Icons.trending_down,
              color: beating ? Colors.green : Colors.orange, size: 32),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Taxa de poupança: ${rate.toStringAsFixed(1)}%',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                    beating
                        ? 'Acima da inflação (IPCA ${ipca.toStringAsFixed(2)}%/mês) ✓'
                        : 'Abaixo da inflação (IPCA ${ipca.toStringAsFixed(2)}%/mês)',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
        ]),
      ),
    );
  }
}

class _CategoryPieChart extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CategoryPieChart({required this.data});

  static const _colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.amber,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    final total =
        entries.fold<double>(0, (s, e) => s + (e.value as num).toDouble());

    return SizedBox(
      height: 200,
      child: Row(children: [
        Expanded(
          child: PieChart(PieChartData(
            sections: entries.asMap().entries.map((e) {
              final pct = (e.value.value as num).toDouble() / total * 100;
              return PieChartSectionData(
                value: pct,
                color: _colors[e.key % _colors.length],
                title: '${pct.toStringAsFixed(0)}%',
                radius: 60,
                titleStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              );
            }).toList(),
          )),
        ),
        const SizedBox(width: 8),
        // Legenda
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries
              .asMap()
              .entries
              .map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: _colors[e.key % _colors.length],
                              shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(e.value.key,
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}

class _MarketCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MarketCard({required this.data});

  @override
  Widget build(BuildContext context) {
    // A Lambda insights retorna market aninhado dentro do body
    final market = data['market'] as Map<String, dynamic>? ?? data;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _MarketRow('IPCA mensal',
              '${(market['ipca_monthly'] as num?)?.toStringAsFixed(2) ?? '--'}%'),
        ]),
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final String label, value;
  const _MarketRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer)),
        ),
      );
}
