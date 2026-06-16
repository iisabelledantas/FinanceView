import 'dart:convert';

import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../auth/domain/auth_models.dart';
import '../../../core/config/app_config.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

class AuthRepository {
  final _storage = const FlutterSecureStorage();

  final _userPool = CognitoUserPool(
    AppConfig.cognitoUserPoolId,
    AppConfig.cognitoClientId,
  );

  Future<AuthUser> signIn(String email, String password) async {
    final cognitoUser = CognitoUser(email, _userPool);
    final authDetails = AuthenticationDetails(
      username: email,
      password: password,
    );

    final session = await cognitoUser.authenticateUser(authDetails);
    if (session == null) throw Exception('Sessão nula após autenticação');

    final idToken = session.idToken.jwtToken!;
    final accessToken = session.accessToken.jwtToken!;
    final refreshToken = session.refreshToken!.token!;

    final claims = session.idToken.payload;
    final userId = claims['sub'] as String;
    final userEmail = claims['email'] as String;
    await _storage.write(key: 'id_token', value: idToken);
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    await _storage.write(key: 'user_id', value: userId);
    await _storage.write(key: 'email', value: userEmail);

    return AuthUser(
      userId: userId,
      email: userEmail,
      idToken: idToken,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> signUp(String email, String password) async {
    await _userPool.signUp(
      email,
      password,
      userAttributes: [AttributeArg(name: 'email', value: email)],
    );
  }

  Future<void> confirmSignUp(String email, String code) async {
    final cognitoUser = CognitoUser(email, _userPool);
    await cognitoUser.confirmRegistration(code);
  }

  Future<AuthUser?> getCurrentUser() async {
    final idToken = await getAuthorizationToken();
    final userId = await _storage.read(key: 'user_id');
    if (idToken == null || userId == null) return null;

    final parts = idToken.split('.');
    if (parts.length != 3) return null;

    return AuthUser(
      userId: userId,
      email: await _storage.read(key: 'email') ?? '',
      idToken: idToken,
      accessToken: await _storage.read(key: 'access_token') ?? '',
      refreshToken: await _storage.read(key: 'refresh_token') ?? '',
    );
  }

  Future<String?> getAuthorizationToken() async {
    final idToken = await _storage.read(key: 'id_token');
    if (idToken == null) return null;

    if (!_isJwtExpired(idToken)) return idToken;

    return _refreshTokens();
  }

  Future<String?> _refreshTokens() async {
    final email = await _storage.read(key: 'email');
    final refreshToken = await _storage.read(key: 'refresh_token');

    if (email == null || refreshToken == null) {
      await signOut();
      return null;
    }

    try {
      final cognitoUser = CognitoUser(email, _userPool);
      final session = await cognitoUser.refreshSession(
        CognitoRefreshToken(refreshToken),
      );

      final idToken = session?.idToken.jwtToken;
      final accessToken = session?.accessToken.jwtToken;

      if (idToken == null || accessToken == null) {
        await signOut();
        return null;
      }

      await _storage.write(key: 'id_token', value: idToken);
      await _storage.write(key: 'access_token', value: accessToken);

      final rotatedRefreshToken = session?.refreshToken?.token;
      if (rotatedRefreshToken != null && rotatedRefreshToken.isNotEmpty) {
        await _storage.write(key: 'refresh_token', value: rotatedRefreshToken);
      }

      return idToken;
    } catch (_) {
      await signOut();
      return null;
    }
  }

  bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final expiration = claims['exp'] as int?;
      if (expiration == null) return true;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const refreshSkewSeconds = 60;
      return expiration <= now + refreshSkewSeconds;
    } catch (_) {
      return true;
    }
  }

  Future<void> signOut() async {
    await _storage.deleteAll();
  }
}
