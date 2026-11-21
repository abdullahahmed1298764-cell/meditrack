import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/app_user.dart';
import 'package:meditrack/providers/auth_provider.dart';
import 'package:meditrack/screens/patient/book_appointment_screen.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreService.reloadDemoData();
  });

  testWidgets('patient can request an appointment', (tester) async {
    final firestoreService = FirestoreService();
    const doctorId = 'real-doctor-user-id';
    await firestoreService.saveUserProfile(
      AppUser(
        uid: doctorId,
        name: 'Dr. Morgan Lee',
        email: 'Morgan@Example.com ',
        role: 'Doctor',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    final auth = AppAuthProvider();
    await auth.initialization;
    auth.appUser = AppUser(
      uid: 'appointment-patient',
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
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const BookAppointmentScreen(),
                  ),
                ),
                child: const Text('Open booking'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open booking'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' MORGAN@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Annual checkup');
    await tester.tap(find.text('Request Appointment'));
    await tester.pumpAndSettle();

    expect(find.text('Open booking'), findsOneWidget);
    expect(find.text('Appointment request sent.'), findsOneWidget);
    expect(FirestoreService.demoAppointments, hasLength(1));
    final appointment = FirestoreService.demoAppointments.values.single;
    expect(appointment.patientId, 'appointment-patient');
    expect(appointment.patientName, 'Taylor Patient');
    expect(appointment.doctorId, doctorId);
    expect(appointment.doctorName, 'Dr. Morgan Lee');
    expect(appointment.status, 'pending');
    expect(appointment.reason, 'Annual checkup');
    expect(appointment.dateTime.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('unknown doctor email shows an error and does not submit', (
    tester,
  ) async {
    final auth = AppAuthProvider();
    await auth.initialization;
    auth.appUser = AppUser(
      uid: 'appointment-patient',
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
        child: const MaterialApp(home: BookAppointmentScreen()),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'unknown@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Annual checkup');
    await tester.tap(find.text('Request Appointment'));
    await tester.pumpAndSettle();

    const notFoundMessage =
        'Doctor not found. Please check the email and try again.';
    expect(find.text(notFoundMessage), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      Colors.red,
    );
    expect(find.byType(BookAppointmentScreen), findsOneWidget);
    expect(FirestoreService.demoAppointments, isEmpty);
  });

  test('email lookup matches normalized emails without checking role', () async {
    final service = FirestoreService();
    const userId = 'matched-user-id';
    await service.saveUserProfile(
      AppUser(
        uid: userId,
        name: 'Matched User',
        email: ' Morgan@Example.com ',
        role: 'Patient',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final user = await service.findUserByEmail('  MORGAN@example.com  ');
    expect(user?.uid, userId);
  });
}
