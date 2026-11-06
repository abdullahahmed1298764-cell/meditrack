import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/models/medicine.dart';
import 'package:meditrack/services/medicine_notification_service.dart';
import 'package:meditrack/services/medicine_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MedicineReminderService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = MedicineReminderService();
  });

  test(
    'saves patient-owned medicines and avoids duplicate scheduled doses',
    () async {
      final patientId = 'patient-schedule-test';
      await service.saveMedicine(
        _medicine(
          patientId: patientId,
          startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 2)),
          frequency: 'Twice daily',
          times: const ['08:00', '20:00'],
        ),
      );

      final medicines = await service.fetchMedicines(patientId);
      final firstFetch = await service.fetchDoses(patientId);
      final secondFetch = await service.fetchDoses(patientId);

      expect(medicines, hasLength(1));
      expect(firstFetch, hasLength(4));
      expect(secondFetch.map((dose) => dose.id).toSet(), hasLength(4));
      expect(await service.fetchMedicines('different-patient'), isEmpty);
      expect(firstFetch.every((dose) => dose.patientId == patientId), isTrue);
      expect(firstFetch.every((dose) => dose.status == 'pending'), isTrue);
    },
  );

  test('records taken, skipped, and snoozed actions without marking taken automatically', () async {
    final patientId = 'patient-actions-test';
    await service.saveMedicine(
      _medicine(
        patientId: patientId,
        startDate: DateTime.now().add(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
        frequency: 'Three times daily',
        times: const ['08:00', '14:00', '20:00'],
      ),
    );
    final doses = await service.fetchDoses(patientId);
    expect(doses.every((dose) => dose.status == 'pending'), isTrue);

    await service.recordDoseAction(
      patientId: patientId,
      medicineId: doses[0].medicineId,
      doseId: doses[0].id,
      action: 'taken',
    );
    await service.recordDoseAction(
      patientId: patientId,
      medicineId: doses[1].medicineId,
      doseId: doses[1].id,
      action: 'skipped',
    );
    await service.recordDoseAction(
      patientId: patientId,
      medicineId: doses[2].medicineId,
      doseId: doses[2].id,
      action: 'snooze',
    );

    final updated = await service.fetchDoses(patientId);
    expect(updated[0].status, 'taken');
    expect(updated[0].takenAt, isNotNull);
    expect(updated[1].status, 'skipped');
    expect(updated[2].status, 'pending');
    expect(updated[2].snoozedUntil, isNotNull);
    expect(
      updated[2].snoozedUntil!.difference(updated[2].actedAt!),
      const Duration(minutes: 10),
    );
  });

  test(
    'only the configured reminder window can transition a dose to missed',
    () async {
      final now = DateTime.now();
      final patientId = 'patient-missed-test';
      await service.saveMedicine(
        _medicine(
          patientId: patientId,
          startDate: DateTime(now.year, now.month, now.day - 1),
          endDate: DateTime(now.year, now.month, now.day),
          frequency: 'Once daily',
          times: const ['00:00'],
        ),
      );

      final doses = await service.fetchDoses(patientId);
      final previousDay = doses.firstWhere(
        (dose) => dose.scheduledAt.day != now.day,
      );
      expect(previousDay.status, 'missed');
      expect(doses.where((dose) => dose.status == 'taken'), isEmpty);
    },
  );

  test('a patient cannot act on another patient medicine or dose', () async {
    await service.saveMedicine(
      _medicine(
        patientId: 'patient-owner',
        startDate: DateTime.now().add(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
        frequency: 'Once daily',
        times: const ['08:00'],
      ),
    );
    final ownerDose = (await service.fetchDoses('patient-owner')).single;

    await expectLater(
      service.recordDoseAction(
        patientId: 'other-patient',
        medicineId: ownerDose.medicineId,
        doseId: ownerDose.id,
        action: 'taken',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await service.fetchDoses('patient-owner')).single.status,
      'pending',
    );
  });

  test('editing a schedule regenerates cancelled future doses', () async {
    final patientId = 'patient-edit-test';
    await service.saveMedicine(
      _medicine(
        patientId: patientId,
        startDate: DateTime.now().add(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
        frequency: 'Once daily',
        times: const ['08:00'],
      ),
    );
    final original = (await service.fetchMedicines(patientId)).single;
    expect(await service.fetchDoses(patientId), hasLength(1));

    await service.saveMedicine(
      Medicine(
        id: original.id,
        patientId: original.patientId,
        name: original.name,
        dosage: original.dosage,
        frequency: original.frequency,
        reminderTimes: original.reminderTimes,
        startDate: original.startDate,
        endDate: original.endDate.add(const Duration(days: 2)),
        instructions: original.instructions,
        notes: original.notes,
        status: original.status,
        createdAt: original.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
    final rescheduled = await service.fetchDoses(patientId);
    expect(rescheduled, hasLength(3));
    expect(rescheduled.every((dose) => dose.status == 'pending'), isTrue);
  });

  test('rejects duplicate reminder times', () async {
    await expectLater(
      service.saveMedicine(
        _medicine(
          patientId: 'patient-invalid-test',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 1)),
          frequency: 'Custom',
          times: const ['08:00', '08:00'],
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('notification identifiers are stable for the same scheduled dose', () {
    final first = MedicineNotificationService.notificationId(
      'medicine_20261027_0800',
    );
    final second = MedicineNotificationService.notificationId(
      'medicine_20261027_0800',
    );
    expect(first, second);
    expect(first, greaterThanOrEqualTo(0));
  });
}

Medicine _medicine({
  required String patientId,
  required DateTime startDate,
  required DateTime endDate,
  required String frequency,
  required List<String> times,
}) {
  final now = DateTime.now();
  return Medicine(
    id: '',
    patientId: patientId,
    name: 'Test medicine',
    dosage: '1 tablet',
    frequency: frequency,
    reminderTimes: times,
    startDate: startDate,
    endDate: endDate,
    instructions: 'After food',
    notes: '',
    status: 'active',
    createdAt: now,
    updatedAt: now,
  );
}
