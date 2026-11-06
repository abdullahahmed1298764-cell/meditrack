import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class AuthService {
  FirebaseAuth? get _firebaseAuth =>
      Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig ? FirebaseAuth.instance : null;

  User? get currentUser => _firebaseAuth?.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth?.authStateChanges() ?? const Stream.empty();

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final auth = _firebaseAuth;
    if (auth == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'no-app',
        message: 'No Firebase app has been initialized.',
      );
    }

    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final auth = _firebaseAuth;
    if (auth == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'no-app',
        message: 'No Firebase app has been initialized.',
      );
    }

    return auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  Future<void> signOut() async {
    final auth = _firebaseAuth;
    if (auth == null) return;
    await auth.signOut();
  }
}
