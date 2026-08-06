import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class OAuthSignInService {
  OAuthSignInService({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? _createGoogleSignIn();

  static const String _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  final GoogleSignIn _googleSignIn;

  static GoogleSignIn _createGoogleSignIn() {
    if (_webClientId.isNotEmpty) {
      return GoogleSignIn(
        scopes: const ['email'],
        serverClientId: _webClientId,
      );
    }
    return GoogleSignIn(scopes: const ['email']);
  }

  Future<OAuthGoogleResult?> signInWithGoogle({
    bool forceAccountPicker = false,
  }) async {
    if (kIsWeb) {
      return null;
    }
    try {
      if (forceAccountPicker) {
        try {
          await _googleSignIn.signOut();
          await _googleSignIn.disconnect();
        } catch (_) {}
      }
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final auth = await googleUser.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) return null;
      return OAuthGoogleResult(idToken: idToken, accessToken: auth.accessToken);
    } catch (_) {
      return null;
    }
  }

  Future<OAuthAppleResult?> signInWithApple() async {
    if (kIsWeb) return null;
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      return OAuthAppleResult(
        idToken: credential.identityToken,
        email: credential.email,
        fullName: _appleFullName(credential),
        rawNonce: rawNonce,
        authorizationCode: credential.authorizationCode,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return null;
      }
      throw StateError(_appleAuthorizationMessage(error));
    }
  }

  Future<UserCredential> firebaseSignInWithGoogle(String idToken) async {
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<UserCredential> firebaseSignInWithApple({
    required String idToken,
    required String rawNonce,
    String? authorizationCode,
  }) async {
    final credential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
      accessToken: authorizationCode,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<UserCredential> firebaseSignInWithEmailPassword(
    String email,
    String password,
  ) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> firebaseRegisterWithEmailPassword(
    String email,
    String password,
  ) {
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> firebaseSendPasswordReset(String email) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  Future<UserCredential> linkGoogleCredential(String idToken) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No Firebase user to link Google credential');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return user.linkWithCredential(credential);
  }

  Future<UserCredential> linkAppleCredential({
    required String idToken,
    required String rawNonce,
    String? authorizationCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No Firebase user to link Apple credential');
    }
    final credential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
      accessToken: authorizationCode,
    );
    return user.linkWithCredential(credential);
  }

  String? _appleFullName(AuthorizationCredentialAppleID credential) {
    final given = credential.givenName;
    final family = credential.familyName;
    if (given == null && family == null) return null;
    return [given, family].whereType<String>().join(' ').trim();
  }

  String _appleAuthorizationMessage(
    SignInWithAppleAuthorizationException error,
  ) {
    switch (error.code) {
      case AuthorizationErrorCode.failed:
        return 'Apple sign-in failed. Try again.';
      case AuthorizationErrorCode.invalidResponse:
        return 'Apple sign-in returned an invalid response.';
      case AuthorizationErrorCode.notHandled:
        return 'Apple sign-in is not configured for this app.';
      case AuthorizationErrorCode.notInteractive:
        return 'Apple sign-in is not available right now. Try again.';
      case AuthorizationErrorCode.unknown:
        return 'Apple sign-in is not enabled for this build. Reinstall the app after enabling Sign in with Apple in Xcode.';
      case AuthorizationErrorCode.canceled:
        return 'Apple sign-in was canceled.';
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

class OAuthGoogleResult {
  const OAuthGoogleResult({required this.idToken, this.accessToken});

  final String idToken;
  final String? accessToken;
}

class OAuthAppleResult {
  const OAuthAppleResult({
    required this.idToken,
    this.email,
    this.fullName,
    required this.rawNonce,
    this.authorizationCode,
  });

  final String? idToken;
  final String? email;
  final String? fullName;
  final String rawNonce;
  final String? authorizationCode;
}
