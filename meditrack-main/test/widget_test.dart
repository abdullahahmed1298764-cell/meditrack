// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meditrack/firebase_options.dart';
import 'package:meditrack/main.dart';
import 'package:meditrack/models/patient_profile.dart';
import 'package:meditrack/models/medical_record.dart';
import 'package:meditrack/providers/auth_provider.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:meditrack/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('MedTrack app loads login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MedTrackApp());
    await tester.pumpAndSettle();

    expect(find.text('Meditrack'), findsOneWidget);
    expect(find.text('Medical Records Manager'), findsOneWidget);
  });

  test('demo sign up works without Firebase configuration', () async {
    final auth = AppAuthProvider();

    await auth.signUp(
      name: 'Test User',
      email: 'test@example.com',
      password: 'Password123!',
      role: 'Patient',
    );

    expect(DefaultFirebaseOptions.isDemoConfig, isTrue);
    expect(auth.errorMessage, isNull);
    expect(auth.appUser, isNotNull);
    expect(auth.appUser!.email, 'test@example.com');
    expect(auth.appUser!.role, 'Patient');

    final user = auth.appUser!;
    await FirestoreService().savePatientProfile(
      user.uid,
      PatientProfile(
        uid: user.uid,
        age: 35,
        gender: 'Other',
        phone: '5551234567',
        emergencyContactName: 'Emergency Contact',
        emergencyContactPhone: '5559876543',
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    final persistedUsers =
        jsonDecode(preferences.getString('demo_users')!) as Map;
    final persistedPasswords =
        jsonDecode(preferences.getString('demo_passwords')!) as Map;
    final persistedProfiles =
        jsonDecode(preferences.getString('demo_profiles')!) as Map;
    expect((persistedUsers['test@example.com'] as Map)['uid'], user.uid);
    expect(persistedPasswords['test@example.com'], isNot('Password123!'));
    expect((persistedProfiles[user.uid] as Map)['age'], 35);
    expect(preferences.getString('demo_session_uid'), user.uid);

    final restartedAuth = AppAuthProvider();
    await restartedAuth.initialization;
    expect(restartedAuth.appUser?.uid, auth.appUser!.uid);
  });

  test('demo mode uploads are available as in-memory data URLs', () async {
    final storage = StorageService();
    final bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);

    final document = await storage.createDocumentForFile(
      patientId: 'demo-patient',
      recordId: 'demo-record',
      fileName: 'report.pdf',
      extension: 'pdf',
      bytes: bytes,
    );

    expect(document.fileName, 'report.pdf');
    expect(
      document.fileUrl,
      'data:application/pdf;base64,${base64Encode(bytes)}',
    );
    expect(document.recordId, 'demo-record');
  });

  test(
    'demo records and uploaded documents are available after saving',
    () async {
      final service = FirestoreService();
      final record = MedicalRecord(
        recordId: 'demo-record-with-document',
        patientId: 'demo-patient-with-document',
        doctorOrHospital: 'Demo Clinic',
        visitDate: DateTime(2026),
        reason: 'Checkup',
        diagnosis: 'Healthy',
        prescription: 'None',
        addedBy: 'demo-patient-with-document',
        createdAt: DateTime(2026),
      );
      final document = await StorageService().createDocumentForFile(
        patientId: record.patientId,
        recordId: record.recordId,
        fileName: 'report.pdf',
        extension: 'pdf',
        bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      );

      await service.addRecord(record);
      await service.saveDocument(document);

      await FirestoreService.reloadDemoData();
      final restartedService = FirestoreService();
      final loadedRecords = await restartedService.fetchRecordsForPatient(
        record.patientId,
      );
      final loadedDocuments = await restartedService.fetchDocumentsForRecord(
        record.recordId,
      );
      expect(
        loadedRecords.map((loaded) => loaded.recordId),
        contains(record.recordId),
      );
      expect(
        loadedDocuments.map((loaded) => loaded.documentId),
        contains(document.documentId),
      );
    },
  );

  test('web file selection without path uses bytes instead', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final file = PlatformFile(
      name: 'report.pdf',
      size: bytes.length,
      bytes: bytes,
      path: null,
    );

    final result = StorageService.readFileBytesForPicker(file);

    expect(result, isNotNull);
    expect(result, equals(bytes));
  });
}
