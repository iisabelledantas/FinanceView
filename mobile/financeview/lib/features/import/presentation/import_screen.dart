import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

enum ImportStatus {
  idle,
  pickingFile,
  uploading,
  processing,
  reviewing,
  confirming,
  success,
  error,
}

class ImportReviewTransaction {
  final String transactionId;
  final String externalId;
  final String bookingDate;
  final String description;
  final String category;
  final String creditDebitType;
  final String transactionType;
  final String status;
  final String amount;
  final String currency;
  final double rawAmount;

  const ImportReviewTransaction({
    required this.transactionId,
    required this.externalId,
    required this.bookingDate,
    required this.description,
    required this.category,
    required this.creditDebitType,
    required this.transactionType,
    required this.status,
    required this.amount,
    required this.currency,
    required this.rawAmount,
  });

  factory ImportReviewTransaction.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'] as Map<String, dynamic>? ?? {};
    return ImportReviewTransaction(
      transactionId: json['transactionId'] as String? ?? '',
      externalId: json['externalId'] as String? ?? '',
      bookingDate: json['bookingDate'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'outros',
      creditDebitType: json['creditDebitType'] as String? ?? 'DEBIT',
      transactionType: json['transactionType'] as String? ?? 'UNKNOWN',
      status: json['status'] as String? ?? 'COMPLETED',
      amount: amount['amount']?.toString() ?? '0.00',
      currency: amount['currency'] as String? ?? 'BRL',
      rawAmount: double.tryParse(json['rawAmount'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transactionId': transactionId,
      'externalId': externalId,
      'bookingDate': bookingDate,
      'description': description,
      'category': category,
      'creditDebitType': creditDebitType,
      'transactionType': transactionType,
      'status': status,
      'amount': {
        'amount': amount,
        'currency': currency,
      },
      'rawAmount': rawAmount,
    };
  }

  ImportReviewTransaction copyWith({
    String? description,
    String? category,
    String? creditDebitType,
  }) {
    final nextType = creditDebitType ?? this.creditDebitType;
    final normalizedRawAmount =
        nextType == 'CREDIT' ? rawAmount.abs() : -rawAmount.abs();

    return ImportReviewTransaction(
      transactionId: transactionId,
      externalId: externalId,
      bookingDate: bookingDate,
      description: description ?? this.description,
      category: category ?? this.category,
      creditDebitType: nextType,
      transactionType: transactionType,
      status: status,
      amount: amount,
      currency: currency,
      rawAmount: normalizedRawAmount,
    );
  }
}

class ImportState {
  final ImportStatus status;
  final String message;
  final List<ImportReviewTransaction> transactions;
  final List<String> categories;

  const ImportState({
    this.status = ImportStatus.idle,
    this.message = '',
    this.transactions = const [],
    this.categories = const [],
  });

  ImportState copyWith({
    ImportStatus? status,
    String? message,
    List<ImportReviewTransaction>? transactions,
    List<String>? categories,
  }) {
    return ImportState(
      status: status ?? this.status,
      message: message ?? this.message,
      transactions: transactions ?? this.transactions,
      categories: categories ?? this.categories,
    );
  }
}

class ImportNotifier extends StateNotifier<ImportState> {
  final ApiClient _api;
  final _storage = const FlutterSecureStorage();

  ImportNotifier(this._api) : super(const ImportState());

  Future<void> importFile() async {
    state = const ImportState(status: ImportStatus.pickingFile);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ofx', 'csv', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      state = const ImportState();
      return;
    }

    final file = result.files.first;
    final fileName = file.name;
    final fileType = fileName.split('.').last.toLowerCase();
    final userId = await _storage.read(key: 'user_id') ?? '';

    try {
      state = state.copyWith(
        status: ImportStatus.uploading,
        message: 'Obtendo URL de upload...',
      );

      final urlResponse = await _api.post('/upload-url', data: {
        'user_id': userId,
        'filename': fileName,
        'file_type': fileType,
      });
      final uploadUrl = urlResponse.data['upload_url'] as String;
      final s3Key = urlResponse.data['s3_key'] as String;

      state = state.copyWith(
        status: ImportStatus.uploading,
        message: 'Enviando arquivo...',
      );

      final dio = Dio();
      await dio.put(
        uploadUrl,
        data: Stream.fromIterable([file.bytes!]),
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
          },
        ),
      );

      state = state.copyWith(
        status: ImportStatus.processing,
        message: 'Preparando revisão...',
      );

      final previewResponse = await _api.post('/statements', data: {
        'action': 'preview',
        'user_id': userId,
        's3_key': s3Key,
        'file_type': fileType,
        'bank': _detectBank(fileName),
      });

      if (previewResponse.statusCode == 202) {
        state = const ImportState(
          status: ImportStatus.success,
          message: 'Extrato recebido. O OCR será concluído em segundo plano.',
        );
        return;
      }

      final data = previewResponse.data as Map<String, dynamic>;
      final transactions = (data['transactions'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ImportReviewTransaction.fromJson)
          .toList();
      final categories = (data['categories'] as List? ?? [])
          .map((category) => category.toString())
          .toList();

      state = ImportState(
        status: ImportStatus.reviewing,
        message: '${transactions.length} transações aguardando revisão',
        transactions: transactions,
        categories: categories,
      );
    } catch (e) {
      state = ImportState(
        status: ImportStatus.error,
        message: _formatImportError(e),
      );
    }
  }

  Future<void> confirmImport() async {
    final userId = await _storage.read(key: 'user_id') ?? '';
    final reviewedTransactions = state.transactions;

    try {
      state = state.copyWith(
        status: ImportStatus.confirming,
        message: 'Salvando transações...',
      );

      final response = await _api.post('/statements', data: {
        'action': 'confirm',
        'user_id': userId,
        'transactions': reviewedTransactions
            .map((transaction) => transaction.toJson())
            .toList(),
      });
      final saved =
          response.data['transactions_saved'] ?? reviewedTransactions.length;

      state = ImportState(
        status: ImportStatus.success,
        message: '$saved transações importadas com sucesso!',
      );
    } catch (e) {
      state = state.copyWith(
        status: ImportStatus.reviewing,
        message: _formatImportError(e),
      );
    }
  }

  void updateTransaction(int index, ImportReviewTransaction transaction) {
    final transactions = [...state.transactions];
    transactions[index] = transaction;
    state = state.copyWith(transactions: transactions);
  }

  String _formatImportError(Object error) {
    if (error is DioException) {
      return 'Erro ao enviar arquivo. Verifique sua conexão e tente novamente.';
    }

    final message = error.toString().replaceFirst('Exception: ', '');
    return 'Erro ao importar: $message';
  }

  String _detectBank(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('inter')) return 'inter';
    if (lower.contains('itau') || lower.contains('itaú')) return 'itau';
    return 'nubank';
  }

  void reset() => state = const ImportState();
}

final importProvider =
    StateNotifierProvider.autoDispose<ImportNotifier, ImportState>(
  (ref) => ImportNotifier(ref.watch(apiClientProvider)),
);

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importProvider);
    final status = state.status;
    final isActive = status == ImportStatus.uploading ||
        status == ImportStatus.processing ||
        status == ImportStatus.pickingFile ||
        status == ImportStatus.confirming;

    return Scaffold(
      appBar: AppBar(title: const Text('Importar extrato')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: status == ImportStatus.reviewing ||
                status == ImportStatus.confirming
            ? _ReviewPanel(
                state: state,
                isConfirming: status == ImportStatus.confirming,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Como exportar seu extrato',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const _BankInstruction('Nubank',
                              'Me -> Exportar extratos -> OFX ou CSV'),
                          const _BankInstruction('Itaú',
                              'Extrato -> Exportar ou salvar em PDF/OFX'),
                          const _BankInstruction('Bradesco',
                              'Extrato -> Salvar como -> OFX ou PDF'),
                          const _BankInstruction(
                              'Inter', 'Extrato -> Exportar -> CSV ou PDF'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: isActive
                        ? null
                        : () => ref.read(importProvider.notifier).importFile(),
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.3),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            status == ImportStatus.success
                                ? Icons.check_circle_outlined
                                : Icons.upload_file_outlined,
                            size: 48,
                            color: status == ImportStatus.success
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          if (isActive) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 8),
                            Text(state.message,
                                style: Theme.of(context).textTheme.bodyMedium),
                          ] else if (status == ImportStatus.success) ...[
                            Text(state.message,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: Colors.green)),
                            TextButton(
                              onPressed: () =>
                                  ref.read(importProvider.notifier).reset(),
                              child: const Text('Importar outro arquivo'),
                            ),
                          ] else if (status == ImportStatus.error) ...[
                            Text(state.message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            TextButton(
                              onPressed: () =>
                                  ref.read(importProvider.notifier).reset(),
                              child: const Text('Tentar novamente'),
                            ),
                          ] else ...[
                            Text('Toque para selecionar arquivo',
                                style: Theme.of(context).textTheme.bodyLarge),
                            const SizedBox(height: 4),
                            Text('OFX, CSV ou PDF',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ReviewPanel extends ConsumerWidget {
  final ImportState state;
  final bool isConfirming;

  const _ReviewPanel({
    required this.state,
    required this.isConfirming,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revisar transações',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          state.message,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: state.transactions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _TransactionReviewItem(
                transaction: state.transactions[index],
                categories: state.categories,
                onChanged: (transaction) => ref
                    .read(importProvider.notifier)
                    .updateTransaction(index, transaction),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isConfirming
                    ? null
                    : () => ref.read(importProvider.notifier).reset(),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: isConfirming
                    ? null
                    : () => ref.read(importProvider.notifier).confirmImport(),
                child: isConfirming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('OK'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransactionReviewItem extends StatelessWidget {
  final ImportReviewTransaction transaction;
  final List<String> categories;
  final ValueChanged<ImportReviewTransaction> onChanged;

  const _TransactionReviewItem({
    required this.transaction,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final categoryOptions =
        categories.isEmpty ? const ['outros'] : categories.toSet().toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    transaction.bookingDate,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  '${transaction.currency} ${transaction.amount}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('${transaction.transactionId}-description'),
              initialValue: transaction.description,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  onChanged(transaction.copyWith(description: value)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: transaction.creditDebitType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'CREDIT',
                        child: Text('Entrada'),
                      ),
                      DropdownMenuItem(
                        value: 'DEBIT',
                        child: Text('Saída'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onChanged(transaction.copyWith(creditDebitType: value));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: categoryOptions.contains(transaction.category)
                        ? transaction.category
                        : 'outros',
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      border: OutlineInputBorder(),
                    ),
                    items: categoryOptions
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onChanged(transaction.copyWith(category: value));
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BankInstruction extends StatelessWidget {
  final String bank, instruction;
  const _BankInstruction(this.bank, this.instruction);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 72,
              child: Text(bank,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
              child: Text(instruction,
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
