import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthInitial()) {
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    state = const AuthLoading();
    try {
      final user = await _repo.getCurrentUser();
      state = user != null
          ? AuthAuthenticated(user)
          : const AuthUnauthenticated();
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> signIn(String email, String password) async {
    state = const AuthLoading();
    try {
      final user = await _repo.signIn(email, password);
      state = AuthAuthenticated(user);
    } catch (e) {
      state = AuthError(_mapError(e));
    }
  }

  Future<void> signUp(String email, String password) async {
    state = const AuthLoading();
    try {
      await _repo.signUp(email, password);
      state = const AuthUnauthenticated();
    } catch (e) {
      state = AuthError(_mapError(e));
    }
  }

  Future<void> confirmSignUp(String email, String code) async {
    state = const AuthLoading();
    try {
      await _repo.confirmSignUp(email, code);
      state = const AuthUnauthenticated();
    } catch (e) {
      state = AuthError(_mapError(e));
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthUnauthenticated();
  }

  String _mapError(Object e) {
    // CognitoClientException tem um campo 'code' com o tipo do erro
    if (e is CognitoClientException) {
      return switch (e.code) {
        'NotAuthorizedException'   => 'E-mail ou senha incorretos',
        'UserNotFoundException'    => 'Usuário não encontrado',
        'UsernameExistsException'  => 'Este e-mail já está cadastrado',
        'InvalidPasswordException' => 'Senha não atende aos requisitos mínimos',
        'CodeMismatchException'    => 'Código de verificação inválido',
        'ExpiredCodeException'     => 'Código expirado. Solicite um novo.',
        _                          => 'Erro de autenticação: ${e.message}',
      };
    }
    return e.toString();
  }
}