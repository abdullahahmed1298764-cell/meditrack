import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/appointment.dart';
import 'package:meditrack/services/firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = FirestoreService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreService.reloadDemoData();
  });

  test('appointment JSON preserves fields and dateTime', () {
    final appointment = Appointment(
      id: 'appointment-1',
      patientId: 'patient-1',
      patientName: 'Patient One',
      doctorId: 'doctor-1',
      doctorName: 'Dr. Morgan',
      dateTime: DateTime(2026, 12, 1, 10),
      status: 'pending',
      reason: 'Annual checkup',
    );

    final restored = Appointment.fromJson(appointment.toJson());

    expect(restored.id, appointment.id);
    expect(restored.patientId, appointment.patientId);
    expect(restored.patientName, appointment.patientName);
    expect(restored.doctorId, appointment.doctorId);
    expect(restored.doctorName, appointment.doctorName);
    expect(restored.dateTime, appointment.dateTime);
    expect(restored.status, appointment.status);
    expect(restored.reason, appointment.reason);
  });

  test(
    'demo appointments can be created, streamed, updated and reloaded',
    () async {
      final laterAppointment = _appointment(
        id: 'later',
        doctorId: 'doctor-1',
        dateTime: DateTime(2026, 12, 2),
      );
      final earlierAppointment = _appointment(
        id: 'earlier',
        doctorId: 'doctor-1',
        dateTime: DateTime(2026, 12, 1),
      );
      await service.requestAppointment(laterAppointment);
      await service.requestAppointment(earlierAppointment);
      await service.requestAppointment(
        _appointment(id: 'other-doctor', doctorId: 'doctor-2'),
      );

      final appointments = await service
          .streamDoctorAppointments('doctor-1')
          .first;
      expect(appointments.map((appointment) => appointment.id), [
        'earlier',
        'later',
      ]);

      await service.updateAppointmentStatus('earlier', 'confirmed');
      await FirestoreService.reloadDemoData();
      final reloaded = await service.streamDoctorAppointments('doctor-1').first;
      expect(reloaded.first.status, 'confirmed');
    },
  );

  test(
    'appointment streams allow multiple listeners and filter pending',
    () async {
      await service.requestAppointment(
        _appointment(id: 'pending-appointment', doctorId: 'doctor-stream-test'),
      );
      await service.requestAppointment(
        Appointment(
          id: 'confirmed-appointment',
          patientId: 'another-patient',
          patientName: 'Another Patient',
          doctorId: 'doctor-stream-test',
          dateTime: DateTime(2026, 12, 2),
          status: 'confirmed',
          reason: 'Follow-up',
        ),
      );

      final scheduleStream = service.streamDoctorAppointments(
        'doctor-stream-test',
      );
      final scheduleResults = await Future.wait([
        scheduleStream.first,
        scheduleStream.first,
      ]);
      expect(scheduleResults.first, hasLength(2));
      expect(scheduleResults.last, hasLength(2));

      final pendingStream = service.streamPendingDoctorAppointments(
        'doctor-stream-test',
      );
      final pendingResults = await Future.wait([
        pendingStream.first,
        pendingStream.first,
      ]);
      expect(pendingResults.first.map((appointment) => appointment.id), [
        'pending-appointment',
      ]);
      expect(pendingResults.last.map((appointment) => appointment.id), [
        'pending-appointment',
      ]);

      final patientAppointments = await service
          .streamPatientAppointments('patient-1')
          .first;
      expect(patientAppointments.map((appointment) => appointment.id), [
        'pending-appointment',
      ]);
    },
  );
}

Appointment _appointment({
  required String id,
  required String doctorId,
  DateTime? dateTime,
}) => Appointment(
  id: id,
  patientId: 'patient-1',
  patientName: 'Patient One',
  doctorId: doctorId,
  dateTime: dateTime ?? DateTime(2026, 12, 1),
  status: 'pending',
  reason: 'Annual checkup',
);
