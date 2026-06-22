import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  ShareService._();

  static final instance = ShareService._();

  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  Future<ShareServiceResult> shareMonthlySummary({
    required String period,
    required Map<String, dynamic> insights,
  }) async {
    final text = buildMonthlySummary(period: period, insights: insights);
    if (text == null) {
      throw const ShareServiceException(
          'Não há dados financeiros para compartilhar.');
    }

    return _shareOrCopy(text, subject: 'Resumo FinanceView - $period');
  }

  Future<ShareServiceResult> shareAnalysisReport({
    required String period,
    required Map<String, dynamic> insights,
  }) async {
    final text = buildAnalysisReport(period: period, insights: insights);
    if (text == null) {
      throw const ShareServiceException(
          'Não há análise financeira para compartilhar.');
    }

    return _shareOrCopy(text, subject: 'Relatório FinanceView - $period');
  }

  String? buildMonthlySummary({
    required String period,
    required Map<String, dynamic> insights,
  }) {
    final health = _health(insights);
    if (health.isEmpty) return null;

    final income = _number(health['total_income']);
    final expenses = _number(health['total_expenses']);
    final savingsRate = _number(health['savings_rate']);
    final savingsBalance = _number(
      health['total_savings_balance'] ?? health['total_savings_movements'],
    );
    final categories = _map(health['expenses_by_category']);

    final lines = [
      'FinanceView - Resumo mensal',
      'Período: $period',
      '',
      'Receitas: ${_currency.format(income)}',
      'Despesas: ${_currency.format(expenses)}',
      'Taxa de poupança: ${savingsRate.toStringAsFixed(2)}%',
      if (savingsBalance != 0)
        'Cofrinho/Poupança: ${_currency.format(savingsBalance)}',
      if (categories.isNotEmpty) '',
      if (categories.isNotEmpty) 'Gastos por categoria:',
      ..._categoryLines(categories),
    ];

    return lines.join('\n');
  }

  String? buildAnalysisReport({
    required String period,
    required Map<String, dynamic> insights,
  }) {
    final health = _health(insights);
    if (health.isEmpty) return null;

    final monthly = _map(health['monthly_evolution']);
    final vsIpca = _map(health['savings_vs_ipca']);
    if (monthly.isEmpty && vsIpca.isEmpty) {
      return buildMonthlySummary(
        period: period,
        insights: insights,
      );
    }

    final lines = [
      'FinanceView - Relatório de análise',
      'Período: $period',
      '',
      if (vsIpca.isNotEmpty) ...[
        'Saúde financeira:',
        'Taxa de poupança: ${_number(vsIpca['savings_rate_pct']).toStringAsFixed(2)}%',
        'IPCA mensal: ${_number(vsIpca['ipca_monthly_pct']).toStringAsFixed(4)}%',
        'Diferença: ${_number(vsIpca['difference_pct']).toStringAsFixed(2)}%',
        _bool(vsIpca['beating_inflation'])
            ? 'Resultado: acima da inflação'
            : 'Resultado: abaixo da inflação',
        '',
      ],
      if (monthly.isNotEmpty) 'Evolução mensal:',
      ...monthly.entries.map((entry) {
        final value = _map(entry.value);
        return '${entry.key}: receitas ${_currency.format(_number(value['income']))}, '
            'despesas ${_currency.format(_number(value['expenses']))}, '
            'saldo ${_currency.format(_number(value['balance']))}';
      }),
    ];

    return lines.join('\n');
  }

  Map<String, dynamic> _health(Map<String, dynamic> insights) {
    final value = insights['health'];
    return value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }

  Map<String, dynamic> _map(dynamic value) {
    return value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }

  List<String> _categoryLines(Map<String, dynamic> categories) {
    final entries = categories.entries.toList()
      ..sort((a, b) => _number(b.value).compareTo(_number(a.value)));

    return entries
        .map((entry) =>
            '- ${entry.key}: ${_currency.format(_number(entry.value))}')
        .toList();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _bool(dynamic value) => value == true;

  Future<ShareServiceResult> _shareOrCopy(
    String text, {
    required String subject,
  }) async {
    try {
      await Share.share(text, subject: subject);
      return ShareServiceResult.shared;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      return ShareServiceResult.copiedToClipboard;
    }
  }
}

enum ShareServiceResult {
  shared,
  copiedToClipboard,
}

class ShareServiceException implements Exception {
  final String message;

  const ShareServiceException(this.message);

  @override
  String toString() => message;
}
