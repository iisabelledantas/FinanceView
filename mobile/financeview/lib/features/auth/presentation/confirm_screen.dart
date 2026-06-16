import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_provider.dart';
import '../domain/auth_models.dart';

class ConfirmScreen extends ConsumerStatefulWidget {
  final String email;
  const ConfirmScreen({super.key, required this.email});

  @override
  ConsumerState<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends ConsumerState<ConfirmScreen> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_codeCtrl.text.length != 6) return;
    await ref.read(authProvider.notifier).confirmSignUp(
      widget.email, _codeCtrl.text.trim(),
    );
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider) is AuthLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Verificar e-mail')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.mark_email_read_outlined, size: 64,
                color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Código enviado para\n${widget.email}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              TextFormField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: const InputDecoration(
                  labelText: 'Código de 6 dígitos',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onChanged: (v) { if (v.length == 6) _confirm(); },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isLoading ? null : _confirm,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: isLoading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirmar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}