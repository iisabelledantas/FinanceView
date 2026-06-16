import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

// Estado da importação
enum ImportStatus { idle, pickingFile, uploading, processing, success, error }

class ImportNotifier extends StateNotifier<(ImportStatus, String)> {
  final ApiClient _api;
  final _storage = const FlutterSecureStorage();

  ImportNotifier(this._api) : super((ImportStatus.idle, ''));

  Future<void> importFile() async {
    state = (ImportStatus.pickingFile, '');

    // 1. Usuário escolhe o arquivo
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ofx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      state = (ImportStatus.idle, '');
      return;
    }

    final file = result.files.first;
    final fileName = file.name;
    final fileType = fileName.split('.').last.toLowerCase();
    final userId = await _storage.read(key: 'user_id') ?? '';

    try {
      state = (ImportStatus.uploading, 'Obtendo URL de upload...');

      // 2. Solicita presigned URL ao backend
      final urlResponse = await _api.post('/upload-url', data: {
        'user_id': userId,
        'filename': fileName,
        'file_type': fileType,
      });
      final uploadUrl = urlResponse.data['upload_url'] as String;
      final s3Key = urlResponse.data['s3_key'] as String;

      state = (ImportStatus.uploading, 'Enviando arquivo...');

      // 3. Upload direto ao S3 via presigned URL (sem passar pela Lambda)
      final dio = Dio();
      await dio.put(
        uploadUrl,
        data: Stream.fromIterable([file.bytes!]),
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': file.bytes!.length,
          },
        ),
      );

      state = (ImportStatus.processing, 'Processando transações...');

      // 4. Notifica o backend para processar o arquivo
      await _api.post('/statements', data: {
        'user_id': userId,
        's3_key': s3Key,
        'file_type': fileType,
        'bank': _detectBank(fileName),
      });

      state = (ImportStatus.success, 'Extrato importado com sucesso!');
    } catch (e) {
      state = (ImportStatus.error, 'Erro ao importar: $e');
    }
  }

  String _detectBank(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('inter')) return 'inter';
    return 'nubank'; // padrão
  }

  void reset() => state = (ImportStatus.idle, '');
}

final importProvider =
    StateNotifierProvider.autoDispose<ImportNotifier, (ImportStatus, String)>(
  (ref) => ImportNotifier(ref.watch(apiClientProvider)),
);

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (status, message) = ref.watch(importProvider);
    final isActive = status == ImportStatus.uploading ||
        status == ImportStatus.processing ||
        status == ImportStatus.pickingFile;

    return Scaffold(
      appBar: AppBar(title: const Text('Importar extrato')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instruções
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
                    const _BankInstruction(
                        'Nubank', 'Me → Exportar extratos → OFX ou CSV'),
                    const _BankInstruction('Itaú', 'Extrato → Exportar → OFX'),
                    const _BankInstruction(
                        'Bradesco', 'Extrato → Salvar como → OFX'),
                    const _BankInstruction('Inter', 'Extrato → Exportar → CSV'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Área de drop / botão
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
                      Text(message,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ] else if (status == ImportStatus.success) ...[
                      Text('Importado com sucesso!',
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
                      Text(message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      TextButton(
                        onPressed: () =>
                            ref.read(importProvider.notifier).reset(),
                        child: const Text('Tentar novamente'),
                      ),
                    ] else ...[
                      Text('Toque para selecionar arquivo',
                          style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text('OFX ou CSV',
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
