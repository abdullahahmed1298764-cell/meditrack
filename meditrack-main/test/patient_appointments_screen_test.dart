import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/app_user.dart';
import 'package:meditrack/models/appointment.dart';
import 'package:meditrack/providers/auth_provider.dart';
import 'package:meditrack/screens/patient/patient_appointments_screen.dart';
import 'package:meditrack/screens/patient/patient_dashboard.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = FirestoreService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreService.reloadDemoData();
  });

  testWidgets('patient dashboard opens their appointment list', (tester) async {
    const patientId = 'patient-appointments-screen';
    await service.requestAppointment(
      Appointment(
        id: 'patient-appointment',
        patientId: patientId,
        patientName: 'Taylor Patient',
        doctorId: 'doc1',
        doctorName: 'Dr. Sarah Ahmed',
        dateTime: DateTime(2026, 12, 10, 14),
        status: 'pending',
        reason: 'Annual checkup',
      ),
    );
    await service.requestAppointment(
      Appointment(
        id: 'confirmed-patient-appointment',
        patientId: patientId,
        patientName: 'Taylor Patient',
        doctorId: 'doc2',
        doctorName: 'Dr. James Wilson',
        dateTime: DateTime(2026, 12, 12, 10),
        status: 'confirmed',
        reason: 'Follow-up',
      ),
    );
    await service.requestAppointment(
      Appointment(
        id: 'cancelled-patient-appointment',
        patientId: patientId,
        patientName: 'Taylor Patient',
        doctorId: 'doc3',
        doctorName: 'Dr. Ayesha Khan',
        dateTime: DateTime(2026, 12, 13, 9),
        status: 'cancelled',
        reason: 'Consultation',
      ),
    );
    await service.requestAppointment(
      Appointment(
        id: 'other-patient-appointment',
        patientId: 'another-patient',
        patientName: 'Other Patient',
        doctorId: 'doc2',
        doctorName: 'Dr. James Wilson',
        dateTime: DateTime(2026, 12, 11, 10),
        status: 'confirmed',
        reason: 'Follow-up',
      ),
    );

    final auth = AppAuthProvider();
    await auth.initialization;
    auth.appUser = AppUser(
      uid: patientId,
      name: 'Taylor Patient',
      email: 'taylor@example.com',
      role: 'Patient',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: PatientDashboard()),
      ),
    );
    await tester.pumpAndSettle();
    final appointmentsButton = find.text('My Appointments');
    await tester.ensureVisible(appointmentsButton);
    await tester.tap(appointmentsButton);
    await tester.pumpAndSettle();

    expect(find.byType(PatientAppointmentsScreen), findsOneWidget);
    expect(find.text('Dr. Sarah Ahmed'), findsOneWidget);
    expect(find.text('Reason: Annual checkup'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Other Patient'), findsNothing);
    expect(
      tester.widget<Text>(find.text('Pending')).style?.color,
      Colors.orange,
    );
    expect(
      tester.widget<Text>(find.text('Confirmed')).style?.color,
      Colors.green,
    );
    expect(
      tester.widget<Text>(find.text('Cancelled')).style?.color,
      Colors.red,
    );
  });
}
