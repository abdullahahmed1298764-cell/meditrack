import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/app_user.dart';
import 'package:meditrack/models/appointment.dart';
import 'package:meditrack/providers/auth_provider.dart';
import 'package:meditrack/screens/doctor/doctor_dashboard.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final firestore = FirestoreService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreService.reloadDemoData();
  });

  testWidgets('doctor can approve and cancel appointments from schedule', (
    tester,
  ) async {
    const doctorId = 'doctor-dashboard-test';
    await firestore.requestAppointment(
      Appointment(
        id: 'appointment-dashboard-test',
        patientId: 'patient-dashboard-test',
        patientName: 'Taylor Patient',
        doctorId: doctorId,
        dateTime: DateTime(2026, 12, 1, 10),
        status: 'pending',
        reason: 'Annual checkup',
      ),
    );
    final auth = AppAuthProvider();
    await auth.initialization;
    auth.appUser = AppUser(
      uid: doctorId,
      name: 'Doctor Test',
      email: 'doctor@example.com',
      role: 'Doctor',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: DoctorDashboard()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Action Required'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();

    expect(find.text('Taylor Patient'), findsNWidgets(2));
    expect(find.text('Reason: Annual checkup'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Pending')).style?.color,
      Colors.orange,
    );
    expect(find.byIcon(Icons.schedule), findsNWidgets(2));

    await tester.tap(find.text('Patients'));
    await tester.pumpAndSettle();
    expect(find.text('Action Required'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Reason: Annual checkup'), findsOneWidget);

    await tester.tap(find.byTooltip('Approve appointment'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Action Required'), findsNothing);
    expect(
      tester.widget<Text>(find.text('Confirmed')).style?.color,
      Colors.green,
    );

    await tester.tap(find.byTooltip('Cancel appointment'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Cancelled')).style?.color,
      Colors.red,
    );
    expect(find.byTooltip('Approve appointment'), findsNothing);
  });

  testWidgets('declining the final pending request hides Action Required', (
    tester,
  ) async {
    const doctorId = 'doctor-decline-test';
    await firestore.requestAppointment(
      Appointment(
        id: 'appointment-decline-test',
        patientId: 'patient-decline-test',
        patientName: 'Jordan Patient',
        doctorId: doctorId,
        dateTime: DateTime(2026, 12, 2, 11),
        status: 'pending',
        reason: 'Follow-up',
      ),
    );
    final auth = AppAuthProvider();
    await auth.initialization;
    auth.appUser = AppUser(
      uid: doctorId,
      name: 'Doctor Test',
      email: 'doctor@example.com',
      role: 'Doctor',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: DoctorDashboard()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Action Required'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Action Required'), findsNothing);
    final appointments = await firestore
        .streamDoctorAppointments(doctorId)
        .first;
    expect(appointments.single.status, 'cancelled');
  });
}
