import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../dashboard/data/insights_repository.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Análise financeira')),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorView(
          error: e,
          onRetry: () => ref.invalidate(insightsProvider),
        ),
        data: (data) {
          final health = data['health'] as Map<String, dynamic>? ?? {};
          final monthly =
              health['monthly_evolution'] as Map<String, dynamic>? ?? {};
          final vsIpca = health['savings_vs_ipca'] as Map<String, dynamic>?;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Comparação com IPCA
              if (vsIpca != null) ...[
                Text('Saúde financeira',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _MetricRow('Taxa de poupança',
                        '${(vsIpca['savings_rate_pct'] as num).toStringAsFixed(2)}%'),
                    _MetricRow('IPCA mensal',
                        '${(vsIpca['ipca_monthly_pct'] as num).toStringAsFixed(4)}%'),
                    _MetricRow('Diferença',
                        '${(vsIpca['difference_pct'] as num).toStringAsFixed(2)}%'),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          vsIpca['beating_inflation'] == true
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: vsIpca['beating_inflation'] == true
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          vsIpca['beating_inflation'] == true
                              ? 'Você está acima da inflação'
                              : 'Você está abaixo da inflação',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ]),
                )),
                const SizedBox(height: 16),
              ],

              // Gráfico de evolução mensal
              if (monthly.isNotEmpty) ...[
                Text('Evolução mensal',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 220,
                    child: _MonthlyBarChart(data: monthly),
                  ),
                )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label, value;
  const _MetricRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );
}

class _MonthlyBarChart extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MonthlyBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();

    return BarChart(BarChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= entries.length) return const SizedBox();
            return Text(entries[i].key.substring(5), // MM
                style: const TextStyle(fontSize: 10));
          },
        )),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: entries.asMap().entries.map((e) {
        final month = e.value.value as Map<String, dynamic>;
        final income = (month['income'] as num).toDouble();
        final expenses = (month['expenses'] as num).toDouble();
        return BarChartGroupData(x: e.key, barRods: [
          BarChartRodData(toY: income, color: Colors.green, width: 10),
          BarChartRodData(toY: expenses, color: Colors.red, width: 10),
        ]);
      }).toList(),
    ));
  }
}
