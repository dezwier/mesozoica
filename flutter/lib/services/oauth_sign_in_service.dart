import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class OAuthSignInService {
  OAuthSignInService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final GoogleSignIn _googleSignIn;

  static const String _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  Future<String?> signInWithGoogle() async {
    if (kIsWeb) {
      return null;
    }
    if (_webClientId.isNotEmpty) {
      final googleUser = await GoogleSignIn(
        scopes: const ['email'],
        serverClientId: _webClientId,
      ).signIn();
      if (googleUser == null) return null;
      final auth = await googleUser.authentication;
      return auth.idToken;
    }
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;
    final auth = await googleUser.authentication;
    return auth.idToken;
  }

  Future<OAuthAppleResult?> signInWithApple() async {
    if (kIsWeb) return null;
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
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
    );
  }

  Future<UserCredential> firebaseSignInWithGoogle(String idToken) async {
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<UserCredential> firebaseSignInWithApple({
    required String idToken,
    required String rawNonce,
  }) async {
    final credential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
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
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No Firebase user to link Apple credential');
    }
    final credential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );
    return user.linkWithCredential(credential);
  }

  String? _appleFullName(AuthorizationCredentialAppleID credential) {
    final given = credential.givenName;
    final family = credential.familyName;
    if (given == null && family == null) return null;
    return [given, family].whereType<String>().join(' ').trim();
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

class OAuthAppleResult {
  const OAuthAppleResult({
    required this.idToken,
    this.email,
    this.fullName,
    required this.rawNonce,
  });

  final String? idToken;
  final String? email;
  final String? fullName;
  final String rawNonce;
}
