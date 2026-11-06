import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';

class AppAuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  static final Map<String, AppUser> _demoUsers = FirestoreService.demoUsers;
  static final Map<String, String> _demoPasswords =
      FirestoreService.demoPasswords;

  User? firebaseUser;
  AppUser? appUser;
  bool isLoading = false;
  String? errorMessage;
  late final Future<void> initialization;

  AppAuthProvider() {
    initialization = initialize();
  }

  bool get _isFirebaseConfigured =>
      Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig;

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _hashPassword(String password) =>
      sha256.convert(utf8.encode(password.trim())).toString();

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();

    try {
      if (Firebase.apps.isEmpty || DefaultFirebaseOptions.isDemoConfig) {
        firebaseUser = null;
        await FirestoreService.initializeDemoData();
        final sessionUid = await FirestoreService.loadDemoSessionUid();
        AppUser? sessionUser;
        for (final user in _demoUsers.values) {
          if (user.uid == sessionUid) {
            sessionUser = user;
            break;
          }
        }
        appUser = sessionUser;
      } else {
        firebaseUser = _authService.currentUser;
        if (firebaseUser != null) {
          appUser = await _firestoreService.fetchUser(firebaseUser!.uid);
        }
      }
    } catch (_) {
      firebaseUser = null;
      appUser = null;
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    await initialization;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (!_isFirebaseConfigured) {
        await FirestoreService.initializeDemoData();
        final key = _normalizeEmail(email);
        final savedPassword = _demoPasswords[key];
        final demoUser = _demoUsers[key];

        if (demoUser == null || savedPassword == null) {
          if (email.trim().toLowerCase() == 'admin@meditrack.demo' &&
              password.trim() == 'Admin123!') {
            final adminUser = AppUser(
              uid: 'demo-admin',
              name: 'Admin User',
              email: 'admin@meditrack.demo',
              role: AppConstants.adminRole,
              isActive: true,
              createdAt: DateTime.now(),
            );
            _demoUsers[key] = adminUser;
            _demoPasswords[key] = _hashPassword(password);
            await FirestoreService.persistDemoData();
            appUser = adminUser;
            firebaseUser = null;
            await FirestoreService.saveDemoSessionUid(adminUser.uid);
            return;
          }
          throw Exception(
            'Demo account not found. Create an account first or configure Firebase.',
          );
        }

        if (savedPassword != _hashPassword(password)) {
          throw Exception('Invalid password for this demo account.');
        }

        if (!demoUser.isActive) {
          throw Exception(
            'This account has been deactivated. Please contact the administrator.',
          );
        }
        appUser = demoUser;
        firebaseUser = null;
        await FirestoreService.saveDemoSessionUid(demoUser.uid);
        return;
      }

      final credential = await _authService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userDoc = await _firestoreService.fetchUser(credential.user!.uid);
      if (userDoc == null) {
        throw Exception('User profile not found. Please contact admin.');
      }
      if (!userDoc.isActive) {
        await _authService.signOut();
        throw Exception(
          'This account has been deactivated. Please contact the administrator.',
        );
      }

      appUser = userDoc;
      firebaseUser = credential.user;
    } on FirebaseAuthException catch (e) {
      errorMessage = e.message ?? 'Login failed.';
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    await initialization;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (!_isFirebaseConfigured) {
        await FirestoreService.initializeDemoData();
        final key = _normalizeEmail(email);
        if (_demoUsers.containsKey(key)) {
          throw Exception(
            'This demo account already exists. Please sign in instead.',
          );
        }

        final createdUser = AppUser(
          uid: 'demo_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          email: email.trim(),
          role: role,
          isActive: true,
          createdAt: DateTime.now(),
        );

        _demoUsers[key] = createdUser;
        _demoPasswords[key] = _hashPassword(password);
        await FirestoreService.persistDemoData();
        appUser = createdUser;
        firebaseUser = null;
        await FirestoreService.saveDemoSessionUid(createdUser.uid);
        return;
      }

      final cred = await _authService.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final createdUser = AppUser(
        uid: cred.user!.uid,
        name: name,
        email: email,
        role: role,
        isActive: true,
        createdAt: DateTime.now(),
      );

      await _firestoreService.saveUserProfile(createdUser);
      appUser = createdUser;
      firebaseUser = cred.user;
    } on FirebaseAuthException catch (e) {
      errorMessage = e.message ?? 'Registration failed.';
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    if (!_isFirebaseConfigured) {
      await FirestoreService.clearDemoSession();
    }
    firebaseUser = null;
    appUser = null;
    notifyListeners();
  }

  bool get isPatient => appUser?.role == AppConstants.patientRole;
  bool get isDoctor => appUser?.role == AppConstants.doctorRole;
  bool get isAdmin => appUser?.role == AppConstants.adminRole;
}
