class AuthUser {
  final String userId;    
  final String email;
  final String idToken;  
  final String accessToken;
  final String refreshToken;

  const AuthUser({
    required this.userId,
    required this.email,
    required this.idToken,
    required this.accessToken,
    required this.refreshToken,
  });
}

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final AuthUser user;
  const AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}