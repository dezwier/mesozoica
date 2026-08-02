import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/profile.dart';
import 'api_client.dart';
import 'token_storage.dart';

class AuthService {
  static const _userKey = 'user_data';

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final idToken = await cred.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return {'success': false, 'message': 'Could not get sign-in token.'};
      }
      return _exchangeFirebaseToken(idToken);
    } on FirebaseAuthException catch (error) {
      return {'success': false, 'message': _firebaseAuthMessage(error)};
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  static String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'user-not-found':
      case 'wrong-password':
        return 'No account found or wrong password. Try Sign up first, '
            'or check email is dezwier@mesozoica.app (not just "dezwier").';
      case 'email-already-in-use':
        return 'This email is already registered. Switch to Sign in.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is disabled in Firebase Console. '
            'Enable it under Authentication → Sign-in method.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      default:
        return error.message ?? error.code;
    }
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) {
        return {'success': false, 'message': 'Could not get sign-in token.'};
      }
      final exchange = await _exchangeFirebaseToken(idToken);
      if (exchange['success'] != true) return exchange;

      final update = await ApiClient.instance.patch(
        '/api/v1/auth/update-profile',
        body: {
          'username': username,
          if (fullName != null) 'full_name': fullName,
        },
      );
      final user = Profile.fromJson(update['user'] as Map<String, dynamic>);
      await _persist(user, exchange['access_token'] as String);
      return {
        'success': true,
        'user': user,
        'access_token': exchange['access_token'],
        'message': update['message'] as String? ?? 'Registration successful',
      };
    } on FirebaseAuthException catch (error) {
      return {'success': false, 'message': _firebaseAuthMessage(error)};
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> exchangeFirebaseToken(String idToken) async {
    try {
      return await _exchangeFirebaseToken(idToken);
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return {'success': true, 'message': 'Check your email for a reset link.'};
    } on FirebaseAuthException catch (error) {
      return {'success': false, 'message': _firebaseAuthMessage(error)};
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? fullName,
    String? currentPassword,
    String? password,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (email != null) body['email'] = email;
      if (fullName != null) body['full_name'] = fullName;
      if (password != null) body['password'] = password;
      if (currentPassword != null) body['current_password'] = currentPassword;
      final response = await ApiClient.instance.patch(
        '/api/v1/auth/update-profile',
        body: body,
      );
      final user = Profile.fromJson(response['user'] as Map<String, dynamic>);
      await _storeUser(user);
      return {'success': true, 'user': user, 'message': response['message']};
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    }
  }

  Future<Map<String, dynamic>> checkUsername(String username) async {
    try {
      final response = await ApiClient.instance.get(
        '/api/v1/auth/check-username',
        query: {'username': username},
      );
      return {'success': true, 'available': response['available'] == true};
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    }
  }

  Future<Map<String, dynamic>> uploadProfileImage(List<int> bytes) async {
    try {
      final response = await ApiClient.instance.multipart(
        '/api/v1/auth/upload-profile-image',
        bytes,
        'profile.jpg',
      );
      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        final detail = decoded['detail'];
        return {
          'success': false,
          'message': detail?.toString() ?? 'Upload failed',
        };
      }
      final user = Profile.fromJson(decoded['user'] as Map<String, dynamic>);
      await _storeUser(user);
      return {'success': true, 'user': user};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<List<String>> getLinkedAccounts() async {
    final response = await ApiClient.instance.get('/api/v1/auth/linked-accounts');
    final providers = response['providers'];
    if (providers is List) {
      return providers.map((item) => item.toString()).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> linkGoogle({
    required String idToken,
    String? accessToken,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'Not signed in to Firebase.'};
      }
      try {
        final credential = GoogleAuthProvider.credential(
          idToken: idToken,
          accessToken: accessToken,
        );
        await user.linkWithCredential(credential);
      } on FirebaseAuthException catch (error) {
        if (error.code == 'credential-already-in-use') {
          return {
            'success': false,
            'message': 'This Google account is already linked to another user.',
          };
        }
        if (error.code != 'provider-already-linked') {
          return {'success': false, 'message': error.message ?? error.code};
        }
      }
      final firebaseToken = await user.getIdToken(true);
      if (firebaseToken == null || firebaseToken.isEmpty) {
        return {'success': false, 'message': 'Could not refresh Firebase token.'};
      }
      final response = await ApiClient.instance.post(
        '/api/v1/auth/link/google',
        body: {'firebase_id_token': firebaseToken},
      );
      return {
        'success': true,
        'providers': (response['providers'] as List?)?.cast<String>() ?? [],
        'message': response['message'] as String? ?? 'Google linked',
      };
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> linkApple({
    required String idToken,
    required String rawNonce,
    String? authorizationCode,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'Not signed in to Firebase.'};
      }
      try {
        final credential = OAuthProvider('apple.com').credential(
          idToken: idToken,
          rawNonce: rawNonce,
          accessToken: authorizationCode,
        );
        await user.linkWithCredential(credential);
      } on FirebaseAuthException catch (error) {
        if (error.code == 'credential-already-in-use') {
          return {
            'success': false,
            'message': 'This Apple account is already linked to another user.',
          };
        }
        if (error.code != 'provider-already-linked') {
          return {'success': false, 'message': error.message ?? error.code};
        }
      }
      final firebaseToken = await user.getIdToken(true);
      if (firebaseToken == null || firebaseToken.isEmpty) {
        return {'success': false, 'message': 'Could not refresh Firebase token.'};
      }
      final response = await ApiClient.instance.post(
        '/api/v1/auth/link/apple',
        body: {'firebase_id_token': firebaseToken},
      );
      return {
        'success': true,
        'providers': (response['providers'] as List?)?.cast<String>() ?? [],
        'message': response['message'] as String? ?? 'Apple linked',
      };
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  Future<Map<String, dynamic>> unlinkProvider(String provider) async {
    try {
      final response = await ApiClient.instance.delete('/api/v1/auth/link/$provider');
      return {
        'success': true,
        'providers': (response['providers'] as List?)?.cast<String>() ?? [],
        'message': response['message'] as String? ?? 'Provider unlinked',
      };
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    }
  }

  Future<Map<String, dynamic>> deleteAccount() async {
    try {
      await ApiClient.instance.delete('/api/v1/auth/delete-account');
      await clearStoredAuth();
      return {'success': true};
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    }
  }

  Future<Map<String, dynamic>> deleteData({
    required bool sites,
    required bool fossils,
    required bool dinosaurs,
  }) async {
    try {
      final response = await ApiClient.instance.post(
        '/api/v1/auth/delete-data',
        body: {
          'sites': sites,
          'fossils': fossils,
          'dinosaurs': dinosaurs,
        },
      );
      final userJson = response['user'] as Map<String, dynamic>?;
      final user = userJson == null ? null : Profile.fromJson(userJson);
      if (user != null) {
        await _storeUser(user);
      }
      return {
        'success': true,
        'user': user,
        'deleted_sites': response['deleted_sites'] as int? ?? 0,
        'deleted_fossils': response['deleted_fossils'] as int? ?? 0,
        'deleted_dinosaurs': response['deleted_dinosaurs'] as int? ?? 0,
        'message': response['message'] as String? ?? 'Data deleted',
      };
    } on ApiException catch (error) {
      return {'success': false, 'message': error.message};
    }
  }

  Future<Profile?> loadStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await TokenStorage.loadToken();
    final userJson = prefs.getString(_userKey);
    if (token == null || userJson == null) return null;
    return Profile.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
  }

  Future<void> clearStoredAuth() async {
    await TokenStorage.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  Future<Profile> refreshProfile() async {
    final response = await ApiClient.instance.get('/api/v1/users/me');
    final user = Profile.fromJson(response);
    await _storeUser(user);
    return user;
  }

  Future<Profile> setSkillXp({
    required String skillId,
    required int xp,
  }) async {
    final response = await ApiClient.instance.patch(
      '/api/v1/users/me/skills/$skillId/xp',
      body: {'xp': xp},
    );
    final user = Profile.fromJson(response);
    await _storeUser(user);
    return user;
  }

  static String imageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final clean = path.startsWith('/') ? path : '/$path';
    return '${AppConfig.baseApiUrl}$clean';
  }

  Future<Map<String, dynamic>> _exchangeFirebaseToken(String idToken) async {
    final response = await ApiClient.instance.post(
      '/api/v1/auth/firebase',
      body: {'id_token': idToken},
      skipAuth: true,
    );
    final user = Profile.fromJson(response['user'] as Map<String, dynamic>);
    final token = response['access_token'] as String? ?? '';
    await _persist(user, token);
    return {
      'success': true,
      'user': user,
      'access_token': token,
      'message': response['message'] as String? ?? 'Login successful',
    };
  }

  Future<void> _persist(Profile user, String token) async {
    await TokenStorage.saveToken(token);
    await _storeUser(user);
  }

  Future<void> _storeUser(Profile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }
}
