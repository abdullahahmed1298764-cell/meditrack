import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/app_user.dart';
import 'package:meditrack/providers/auth_provider.dart';
import 'package:meditrack/screens/admin/add_doctor_screen.dart';
import 'package:meditrack/screens/admin/admin_dashboard.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreService.reloadDemoData();
  });

  testWidgets('admin can add a doctor profile from dashboard', (tester) async {
    final auth = AppAuthProvider();
    await auth.initialization;
    auth.appUser = AppUser(
      uid: 'doctor-profile-admin',
      name: 'Admin User',
      email: 'admin@example.com',
      role: 'Admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: AdminDashboard()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Doctor'));
    await tester.pumpAndSettle();

    expect(find.byType(AddDoctorScreen), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Dr. Morgan Lee');
    await tester.enterText(find.byType(TextFormField).at(1), 'Cardiologist');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'morgan@example.com',
    );
    await tester.tap(find.text('Save Doctor'));
    await tester.pumpAndSettle();

    expect(find.byType(AddDoctorScreen), findsNothing);
    expect(find.text('Doctor profile saved successfully.'), findsOneWidget);
    expect(FirestoreService.demoDoctors, hasLength(1));
    final doctor = FirestoreService.demoDoctors.values.single;
    expect(doctor['name'], 'Dr. Morgan Lee');
    expect(doctor['specialty'], 'Cardiologist');
    expect(doctor['email'], 'morgan@example.com');
    expect(doctor['doctorId'], isNotEmpty);
  });
}
