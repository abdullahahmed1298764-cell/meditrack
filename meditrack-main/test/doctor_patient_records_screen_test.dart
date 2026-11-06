import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/app_user.dart';
import 'package:meditrack/models/medical_record.dart';
import 'package:meditrack/screens/doctor/doctor_patient_records_screen.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('doctor can view a patient report and its details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final patient = AppUser(
      uid: 'doctor-view-patient',
      name: 'Taylor Patient',
      email: 'taylor@example.com',
      role: 'Patient',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    await FirestoreService().addRecord(
      MedicalRecord(
        recordId: 'doctor-view-record',
        patientId: patient.uid,
        doctorOrHospital: 'Community Clinic',
        visitDate: DateTime(2026, 10, 10),
        reason: 'Annual checkup',
        diagnosis: 'Routine follow-up',
        prescription: 'As prescribed',
        addedBy: patient.uid,
        createdAt: DateTime(2026, 10, 10),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: DoctorPatientRecordsScreen(patient: patient)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Annual checkup'), findsOneWidget);
    expect(find.textContaining('Diagnosis: Routine follow-up'), findsOneWidget);
    expect(find.textContaining('1 report'), findsOneWidget);

    await tester.tap(find.text('Annual checkup'));
    await tester.pumpAndSettle();

    expect(find.text('Record details'), findsOneWidget);
    expect(find.text('Routine follow-up'), findsOneWidget);
    expect(find.text('As prescribed'), findsOneWidget);
  });
}
