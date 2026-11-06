import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const _demoApiKey = 'demo-api-key';
  static const _demoProjectId = 'demo-project-id';

  static bool get isDemoConfig =>
      currentPlatform.apiKey == _demoApiKey || currentPlatform.projectId == _demoProjectId;

  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: _demoApiKey,
      appId: '1:000000000000:web:demo-app-id',
      messagingSenderId: '000000000000',
      projectId: _demoProjectId,
      authDomain: 'demo-project-id.firebaseapp.com',
      storageBucket: 'demo-project-id.appspot.com',
      measurementId: 'G-0000000000',
    );
  }
}
