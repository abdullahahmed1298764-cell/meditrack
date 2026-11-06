import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/medical_document.dart';
import 'package:meditrack/providers/auth_provider.dart';
import 'package:meditrack/screens/patient/medical_reports_screen.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:meditrack/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  final firestore = FirestoreService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreService.reloadDemoData();
  });

  test(
    'accepts PDF and X-ray image bytes and returns private demo data',
    () async {
      final pdf = await storage.createDocumentForFile(
        patientId: 'patient-a',
        recordId: '',
        fileName: 'cbc.pdf',
        extension: 'pdf',
        bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
        reportTitle: 'CBC results',
        reportCategory: 'Blood Test',
        reportDate: DateTime(2026, 1, 10),
      );
      final xray = await storage.createDocumentForFile(
        patientId: 'patient-a',
        recordId: '',
        fileName: 'xray.png',
        extension: 'png',
        bytes: Uint8List.fromList([
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]),
        reportTitle: 'Chest X-ray',
        reportCategory: 'X-ray',
      );

      expect(await storage.downloadDocument(pdf), '%PDF-1.7'.codeUnits);
      expect(await storage.downloadDocument(xray), [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      expect(pdf.filePath, isEmpty);
      expect(pdf.fileUrl, startsWith('data:application/pdf;base64,'));
      expect(xray.fileUrl, startsWith('data:image/png;base64,'));
      expect(pdf.reportCategory, 'Blood Test');
    },
  );

  test('rejects spoofed extensions and files over five megabytes', () async {
    await expectLater(
      storage.createDocumentForFile(
        patientId: 'patient-a',
        recordId: '',
        fileName: 'spoofed.pdf',
        extension: 'pdf',
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      ),
      throwsA(isA<FormatException>()),
    );

    final oversized = Uint8List(5 * 1024 * 1024 + 1)
      ..setRange(0, 8, '%PDF-1.7'.codeUnits);
    await expectLater(
      storage.createDocumentForFile(
        patientId: 'patient-a',
        recordId: '',
        fileName: 'large.pdf',
        extension: 'pdf',
        bytes: oversized,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('reports stay patient-scoped and can be updated and deleted', () async {
    final ownerReport = await _createReport(
      patientId: 'owner',
      title: 'Private blood test',
      category: 'Blood Test',
    );
    final otherReport = await _createReport(
      patientId: 'another-patient',
      title: 'Other report',
      category: 'X-ray',
    );
    await firestore.saveDocument(ownerReport);
    await firestore.saveDocument(otherReport);

    expect(
      (await firestore.fetchDocumentsForPatient('owner'))
          .map((report) => report.documentId),
      [ownerReport.documentId],
    );
    expect(await firestore.fetchDocumentsForRecord('', patientId: 'owner'), [
      ownerReport,
    ]);

    await firestore.updateDocument(
      MedicalDocument(
        documentId: ownerReport.documentId,
        recordId: ownerReport.recordId,
        patientId: ownerReport.patientId,
        fileName: ownerReport.fileName,
        fileUrl: ownerReport.fileUrl,
        filePath: ownerReport.filePath,
        fileType: ownerReport.fileType,
        reportTitle: 'Updated blood test',
        reportCategory: ownerReport.reportCategory,
        uploadedAt: ownerReport.uploadedAt,
      ),
    );
    expect(
      (await firestore.fetchDocument(ownerReport.documentId))?.reportTitle,
      'Updated blood test',
    );

    await storage.deleteDocumentFile(ownerReport);
    await firestore.deleteDocument(ownerReport.documentId);
    expect(await firestore.fetchDocument(ownerReport.documentId), isNull);
    expect(await firestore.fetchDocumentsForPatient('another-patient'), [
      otherReport,
    ]);
  });

  test('doctor reports require patient-granted access', () async {
    final patient = AppAuthProvider();
    await patient.initialization;
    await patient.signUp(
      name: 'Report Patient',
      email: 'reports-patient@example.com',
      password: 'Password123!',
      role: 'Patient',
    );
    final patientId = patient.appUser!.uid;

    final doctor = AppAuthProvider();
    await doctor.initialization;
    await doctor.signUp(
      name: 'Report Doctor',
      email: 'reports-doctor@example.com',
      password: 'Password123!',
      role: 'Doctor',
    );
    final doctorId = doctor.appUser!.uid;

    expect(await firestore.fetchPatientsSharedWithDoctor(doctorId), isEmpty);
    await firestore.grantDoctorAccess(patientId: patientId, doctorId: doctorId);
    expect(
      (await firestore.fetchPatientsSharedWithDoctor(doctorId))
          .map((user) => user.uid),
      [patientId],
    );
    expect(await firestore.fetchAuthorizedDoctorIds(patientId), [doctorId]);

    await firestore.revokeDoctorAccess(
      patientId: patientId,
      doctorId: doctorId,
    );
    expect(await firestore.fetchPatientsSharedWithDoctor(doctorId), isEmpty);
  });

  testWidgets('dashboard searches, filters, sorts, and groups reports', (
    tester,
  ) async {
    final auth = AppAuthProvider();
    await auth.initialization;
    await auth.signUp(
      name: 'Dashboard Patient',
      email: 'dashboard-patient@example.com',
      password: 'Password123!',
      role: 'Patient',
    );
    await firestore.saveDocument(
      await _createReport(
        patientId: auth.appUser!.uid,
        title: 'CBC panel',
        category: 'Blood Test',
        doctor: 'Dr One',
        date: DateTime(2026, 1, 20),
      ),
    );
    await firestore.saveDocument(
      await _createReport(
        patientId: auth.appUser!.uid,
        title: 'Glucose test',
        category: 'Blood Test',
        doctor: 'Dr Two',
        date: DateTime(2026, 2, 10),
      ),
    );
    await firestore.saveDocument(
      await _createReport(
        patientId: auth.appUser!.uid,
        title: 'Chest image',
        category: 'X-ray',
        doctor: 'Dr One',
        date: DateTime(2026, 3, 8),
      ),
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(home: MedicalReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CBC panel'), findsOneWidget);
    expect(find.text('January 2026'), findsOneWidget);
    expect(find.text('February 2026'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'glucose');
    await tester.pumpAndSettle();
    expect(find.text('Glucose test'), findsOneWidget);
    expect(find.text('CBC panel'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Blood Test'));
    await tester.pumpAndSettle();
    expect(find.text('CBC panel'), findsOneWidget);
    expect(find.text('Glucose test'), findsOneWidget);
    expect(find.text('Chest image'), findsNothing);

    await tester.tap(find.byTooltip('Sort oldest first'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sort newest first'), findsOneWidget);
  });
}

Future<MedicalDocument> _createReport({
  required String patientId,
  required String title,
  required String category,
  String doctor = '',
  DateTime? date,
}) async {
  final sequence = DateTime.now().microsecondsSinceEpoch + reportCounter++;
  return StorageService().createDocumentForFile(
    patientId: patientId,
    recordId: '',
    fileName: 'report-$sequence.pdf',
    extension: 'pdf',
    bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
    reportTitle: title,
    reportCategory: category,
    doctorName: doctor,
    reportDate: date,
  );
}

int reportCounter = 0;
