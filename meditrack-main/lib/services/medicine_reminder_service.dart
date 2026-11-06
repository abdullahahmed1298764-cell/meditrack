import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../firebase_options.dart';
import '../models/medicine.dart';
import '../models/scheduled_dose.dart';

class MedicineReminderService {
  static const missedWindow = Duration(minutes: 30);
  static const _uuid = Uuid();

  bool get _usesFirestore =>
      Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig;

  CollectionReference<Map<String, dynamic>> _medicines(String patientId) =>
      FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .collection('medicines');

  CollectionReference<Map<String, dynamic>> _doses(
    String patientId,
    String medicineId,
  ) => _medicines(patientId).doc(medicineId).collection('doses');

  String _medicineKey(String patientId) => 'medicine_reminders_v1_$patientId';
  String _doseKey(String patientId) => 'scheduled_doses_v1_$patientId';

  Future<List<Medicine>> fetchMedicines(String patientId) async {
    _requirePatientId(patientId);
    if (!_usesFirestore) {
      final values = await _readDemoMap(_medicineKey(patientId));
      return values.values.map((data) => Medicine.fromJson(data)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final snapshot = await _medicines(patientId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => Medicine.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  Future<void> saveMedicine(Medicine medicine) async {
    _requirePatientId(medicine.patientId);
    _validateMedicine(medicine);
    final now = DateTime.now();
    final saved = Medicine(
      id: medicine.id.isEmpty ? _uuid.v4() : medicine.id,
      patientId: medicine.patientId,
      name: medicine.name.trim(),
      dosage: medicine.dosage.trim(),
      frequency: medicine.frequency,
      reminderTimes: List<String>.from(medicine.reminderTimes)..sort(),
      startDate: _dateOnly(medicine.startDate),
      endDate: _dateOnly(medicine.endDate),
      instructions: medicine.instructions,
      notes: medicine.notes.trim(),
      status: medicine.status,
      createdAt: medicine.id.isEmpty ? now : medicine.createdAt,
      updatedAt: now,
    );

    if (!_usesFirestore) {
      final entries = await _readDemoMap(_medicineKey(saved.patientId));
      final previousData = entries[saved.id];
      if (previousData != null) {
        final previous = Medicine.fromJson(previousData);
        if (!_sameSchedule(previous, saved)) {
          final doses = await _readDemoMap(_doseKey(saved.patientId));
          for (final entry in doses.entries.toList()) {
            final dose = ScheduledDose.fromJson(entry.value);
            if (dose.medicineId == saved.id &&
                dose.status == 'pending' &&
                dose.scheduledAt.isAfter(now)) {
              doses[entry.key] = _copyDose(dose, status: 'cancelled').toJson();
            }
          }
          await _writeDemoMap(_doseKey(saved.patientId), doses);
        }
      }
      entries[saved.id] = saved.toJson();
      await _writeDemoMap(_medicineKey(saved.patientId), entries);
      return;
    }

    final ref = _medicines(saved.patientId).doc(saved.id);
    if (medicine.id.isNotEmpty) {
      final existing = await ref.get();
      if (existing.exists) {
        final previous = Medicine.fromFirestore(existing.id, existing.data()!);
        if (!_sameSchedule(previous, saved)) {
          await _cancelFuturePendingDoses(saved.patientId, saved.id);
        }
      }
    }
    await ref.set(saved.toFirestore());
  }

  Future<void> discontinueMedicine(String patientId, String medicineId) async {
    _requirePatientId(patientId);
    final medicine = await _findMedicine(patientId, medicineId);
    if (medicine == null) throw StateError('Medicine was not found.');

    final updated = Medicine(
      id: medicine.id,
      patientId: medicine.patientId,
      name: medicine.name,
      dosage: medicine.dosage,
      frequency: medicine.frequency,
      reminderTimes: medicine.reminderTimes,
      startDate: medicine.startDate,
      endDate: medicine.endDate,
      instructions: medicine.instructions,
      notes: medicine.notes,
      status: 'discontinued',
      createdAt: medicine.createdAt,
      updatedAt: DateTime.now(),
    );

    if (!_usesFirestore) {
      final medicines = await _readDemoMap(_medicineKey(patientId));
      medicines[medicineId] = updated.toJson();
      await _writeDemoMap(_medicineKey(patientId), medicines);
      final doses = await _readDemoMap(_doseKey(patientId));
      for (final entry in doses.entries.toList()) {
        final dose = ScheduledDose.fromJson(entry.value);
        if (dose.medicineId == medicineId &&
            dose.status == 'pending' &&
            dose.scheduledAt.isAfter(DateTime.now())) {
          doses[entry.key] = _copyDose(dose, status: 'cancelled').toJson();
        }
      }
      await _writeDemoMap(_doseKey(patientId), doses);
      return;
    }

    await _medicines(patientId).doc(medicineId).set(updated.toFirestore());
    await _cancelFuturePendingDoses(patientId, medicineId);
  }

  Future<List<ScheduledDose>> fetchDoses(String patientId) async {
    _requirePatientId(patientId);
    final medicines = await fetchMedicines(patientId);
    await _ensureDoseWindow(patientId, medicines);
    await _markExpiredDosesMissed(patientId, medicines);
    return _loadDoses(patientId, medicines);
  }

  Future<void> recordDoseAction({
    required String patientId,
    required String medicineId,
    required String doseId,
    required String action,
  }) async {
    _requirePatientId(patientId);
    if (!const {'taken', 'skipped', 'snooze'}.contains(action)) {
      throw ArgumentError.value(action, 'action', 'Unsupported dose action.');
    }
    final medicine = await _findMedicine(patientId, medicineId);
    if (medicine == null) throw StateError('Medicine was not found.');
    final dose = await _findDose(patientId, medicineId, doseId);
    if (dose == null) throw StateError('Scheduled dose was not found.');
    if (dose.patientId != patientId || dose.medicineId != medicineId) {
      throw StateError('Scheduled dose does not belong to this patient.');
    }
    if (dose.status != 'pending') {
      throw StateError('This dose has already been recorded.');
    }

    final now = DateTime.now();
    final updated = switch (action) {
      'taken' => _copyDose(
        dose,
        status: 'taken',
        takenAt: now,
        actedAt: now,
        clearSnooze: true,
      ),
      'skipped' => _copyDose(
        dose,
        status: 'skipped',
        actedAt: now,
        clearSnooze: true,
      ),
      _ => _copyDose(
        dose,
        actedAt: now,
        snoozedUntil: now.add(const Duration(minutes: 10)),
      ),
    };

    if (!_usesFirestore) {
      final doses = await _readDemoMap(_doseKey(patientId));
      doses[doseId] = updated.toJson();
      await _writeDemoMap(_doseKey(patientId), doses);
      return;
    }
    await _doses(patientId, medicineId).doc(doseId).set(updated.toFirestore());
  }

  Future<Medicine?> _findMedicine(String patientId, String medicineId) async {
    final medicines = await fetchMedicines(patientId);
    for (final medicine in medicines) {
      if (medicine.id == medicineId && medicine.patientId == patientId) {
        return medicine;
      }
    }
    return null;
  }

  Future<ScheduledDose?> _findDose(
    String patientId,
    String medicineId,
    String doseId,
  ) async {
    if (!_usesFirestore) {
      final doses = await _readDemoMap(_doseKey(patientId));
      final data = doses[doseId];
      return data == null ? null : ScheduledDose.fromJson(data);
    }
    final snapshot = await _doses(patientId, medicineId).doc(doseId).get();
    return snapshot.exists
        ? ScheduledDose.fromFirestore(snapshot.id, snapshot.data()!)
        : null;
  }

  Future<void> _ensureDoseWindow(
    String patientId,
    List<Medicine> medicines,
  ) async {
    final now = DateTime.now();
    final firstDay = _dateOnly(now.subtract(const Duration(days: 30)));
    final lastDay = _dateOnly(now.add(const Duration(days: 14)));
    final demoDoses = _usesFirestore
        ? null
        : await _readDemoMap(_doseKey(patientId));
    var changed = false;

    for (final medicine in medicines.where((item) => item.status == 'active')) {
      final medicineStart = _dateOnly(medicine.startDate);
      final medicineEnd = _dateOnly(medicine.endDate);
      var day = medicineStart.isAfter(firstDay) ? medicineStart : firstDay;
      final end = medicineEnd.isBefore(lastDay) ? medicineEnd : lastDay;
      if (day.isAfter(end)) continue;

      final existing = <String>{};
      if (_usesFirestore) {
        final snapshot = await _doses(patientId, medicine.id)
            .where(
              'scheduledAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(day),
            )
            .where(
              'scheduledAt',
              isLessThan: Timestamp.fromDate(end.add(const Duration(days: 1))),
            )
            .get();
        existing.addAll(
          snapshot.docs
              .where((doc) => doc.data()['status'] != 'cancelled')
              .map((doc) => doc.id),
        );
      } else {
        existing.addAll(
          demoDoses!.entries
              .where((entry) {
                final dose = ScheduledDose.fromJson(entry.value);
                return dose.medicineId == medicine.id &&
                    dose.status != 'cancelled' &&
                    !dose.scheduledAt.isBefore(day) &&
                    dose.scheduledAt.isBefore(end.add(const Duration(days: 1)));
              })
              .map((entry) => entry.key),
        );
      }

      final newDoses = <ScheduledDose>[];
      while (!day.isAfter(end)) {
        for (final time in medicine.reminderTimes) {
          final parts = time.split(':');
          final scheduledAt = DateTime(
            day.year,
            day.month,
            day.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          );
          final id =
              '${medicine.id}_${_compactDate(day)}_${parts[0]}${parts[1]}';
          if (!existing.contains(id)) {
            newDoses.add(
              ScheduledDose(
                id: id,
                patientId: patientId,
                medicineId: medicine.id,
                scheduledAt: scheduledAt,
                status: 'pending',
                createdAt: now,
              ),
            );
          }
        }
        day = day.add(const Duration(days: 1));
      }

      if (_usesFirestore) {
        for (var index = 0; index < newDoses.length; index += 400) {
          final batch = FirebaseFirestore.instance.batch();
          for (final dose in newDoses.skip(index).take(400)) {
            batch.set(
              _doses(patientId, medicine.id).doc(dose.id),
              dose.toFirestore(),
            );
          }
          await batch.commit();
        }
      } else {
        for (final dose in newDoses) {
          demoDoses![dose.id] = dose.toJson();
        }
        changed = changed || newDoses.isNotEmpty;
      }
    }
    if (changed) await _writeDemoMap(_doseKey(patientId), demoDoses!);
  }

  Future<void> _markExpiredDosesMissed(
    String patientId,
    List<Medicine> medicines,
  ) async {
    final threshold = DateTime.now().subtract(missedWindow);
    if (!_usesFirestore) {
      final doses = await _readDemoMap(_doseKey(patientId));
      var changed = false;
      for (final entry in doses.entries.toList()) {
        final dose = ScheduledDose.fromJson(entry.value);
        if (dose.status == 'pending' && !dose.scheduledAt.isAfter(threshold)) {
          doses[entry.key] = _copyDose(dose, status: 'missed').toJson();
          changed = true;
        }
      }
      if (changed) await _writeDemoMap(_doseKey(patientId), doses);
      return;
    }

    for (final medicine in medicines) {
      final expired = await _doses(patientId, medicine.id)
          .where('status', isEqualTo: 'pending')
          .where(
            'scheduledAt',
            isLessThanOrEqualTo: Timestamp.fromDate(threshold),
          )
          .get();
      for (var index = 0; index < expired.docs.length; index += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in expired.docs.skip(index).take(400)) {
          batch.update(doc.reference, {'status': 'missed'});
        }
        await batch.commit();
      }
    }
  }

  Future<List<ScheduledDose>> _loadDoses(
    String patientId,
    List<Medicine> medicines,
  ) async {
    final firstVisibleDate = DateTime.now().subtract(const Duration(days: 30));
    if (!_usesFirestore) {
      final allDoses = await _readDemoMap(_doseKey(patientId));
      final medicineIds = medicines.map((medicine) => medicine.id).toSet();
      return allDoses.values
          .map(ScheduledDose.fromJson)
          .where(
            (dose) =>
                dose.patientId == patientId &&
                medicineIds.contains(dose.medicineId) &&
                !dose.scheduledAt.isBefore(firstVisibleDate) &&
                dose.status != 'cancelled',
          )
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    }

    final all = <ScheduledDose>[];
    for (final medicine in medicines) {
      final snapshot = await _doses(patientId, medicine.id)
          .where(
            'scheduledAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstVisibleDate),
          )
          .orderBy('scheduledAt')
          .get();
      all.addAll(
        snapshot.docs.map(
          (doc) => ScheduledDose.fromFirestore(doc.id, doc.data()),
        ),
      );
    }
    all.removeWhere((dose) => dose.status == 'cancelled');
    all.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return all;
  }

  Future<void> _cancelFuturePendingDoses(
    String patientId,
    String medicineId,
  ) async {
    final now = DateTime.now();
    if (!_usesFirestore) {
      final doses = await _readDemoMap(_doseKey(patientId));
      for (final entry in doses.entries.toList()) {
        final dose = ScheduledDose.fromJson(entry.value);
        if (dose.medicineId == medicineId &&
            dose.status == 'pending' &&
            dose.scheduledAt.isAfter(now)) {
          doses[entry.key] = _copyDose(dose, status: 'cancelled').toJson();
        }
      }
      await _writeDemoMap(_doseKey(patientId), doses);
      return;
    }
    final pending = await _doses(patientId, medicineId)
        .where('status', isEqualTo: 'pending')
        .where('scheduledAt', isGreaterThan: Timestamp.fromDate(now))
        .get();
    for (var index = 0; index < pending.docs.length; index += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in pending.docs.skip(index).take(400)) {
        batch.update(doc.reference, {'status': 'cancelled'});
      }
      await batch.commit();
    }
  }

  static ScheduledDose _copyDose(
    ScheduledDose dose, {
    String? status,
    DateTime? takenAt,
    DateTime? actedAt,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) => ScheduledDose(
    id: dose.id,
    patientId: dose.patientId,
    medicineId: dose.medicineId,
    scheduledAt: dose.scheduledAt,
    status: status ?? dose.status,
    createdAt: dose.createdAt,
    takenAt: takenAt ?? dose.takenAt,
    actedAt: actedAt ?? dose.actedAt,
    snoozedUntil: clearSnooze ? null : snoozedUntil ?? dose.snoozedUntil,
  );

  static void _validateMedicine(Medicine medicine) {
    if (medicine.name.trim().isEmpty || medicine.name.trim().length > 120) {
      throw ArgumentError('Enter a medicine name up to 120 characters.');
    }
    if (medicine.dosage.trim().isEmpty || medicine.dosage.trim().length > 80) {
      throw ArgumentError('Enter a dosage up to 80 characters.');
    }
    if (medicine.reminderTimes.isEmpty) {
      throw ArgumentError('Add at least one reminder time.');
    }
    final expectedCount = switch (medicine.frequency) {
      'Once daily' => 1,
      'Twice daily' => 2,
      'Three times daily' => 3,
      _ => null,
    };
    if (expectedCount != null &&
        medicine.reminderTimes.length != expectedCount) {
      throw ArgumentError('Reminder time count does not match the frequency.');
    }
    if (medicine.reminderTimes.length > 24 ||
        medicine.reminderTimes.toSet().length !=
            medicine.reminderTimes.length) {
      throw ArgumentError('Reminder times must be unique, up to 24 per day.');
    }
    for (final time in medicine.reminderTimes) {
      final match = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').firstMatch(time);
      if (match == null) {
        throw ArgumentError('Reminder times must use 24-hour HH:mm format.');
      }
    }
    if (_dateOnly(medicine.endDate).isBefore(_dateOnly(medicine.startDate))) {
      throw ArgumentError('End date cannot be before start date.');
    }
    if (!const {
      'Once daily',
      'Twice daily',
      'Three times daily',
      'Custom',
    }.contains(medicine.frequency)) {
      throw ArgumentError('Choose a valid frequency.');
    }
    if (!const {
      'Before food',
      'After food',
      'As prescribed',
    }.contains(medicine.instructions)) {
      throw ArgumentError('Choose valid medicine instructions.');
    }
    if (medicine.notes.length > 500) {
      throw ArgumentError('Additional notes must be 500 characters or fewer.');
    }
    if (!const {
      'active',
      'completed',
      'discontinued',
    }.contains(medicine.status)) {
      throw ArgumentError('Choose a valid medicine status.');
    }
  }

  static bool _sameSchedule(Medicine first, Medicine second) =>
      first.frequency == second.frequency &&
      first.reminderTimes.join(',') == second.reminderTimes.join(',') &&
      _dateOnly(first.startDate) == _dateOnly(second.startDate) &&
      _dateOnly(first.endDate) == _dateOnly(second.endDate);

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _compactDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static void _requirePatientId(String patientId) {
    if (patientId.trim().isEmpty) {
      throw ArgumentError('A signed-in patient is required.');
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readDemoMap(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final json = preferences.getString(key);
    if (json == null) return {};
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map(
      (id, value) => MapEntry(id, Map<String, dynamic>.from(value as Map)),
    );
  }

  Future<void> _writeDemoMap(
    String key,
    Map<String, Map<String, dynamic>> values,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(values));
  }
}
