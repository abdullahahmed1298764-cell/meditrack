import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduledDose {
  const ScheduledDose({
    required this.id,
    required this.patientId,
    required this.medicineId,
    required this.scheduledAt,
    required this.status,
    required this.createdAt,
    this.takenAt,
    this.actedAt,
    this.snoozedUntil,
  });

  final String id;
  final String patientId;
  final String medicineId;
  final DateTime scheduledAt;
  final String status;
  final DateTime createdAt;
  final DateTime? takenAt;
  final DateTime? actedAt;
  final DateTime? snoozedUntil;

  Map<String, dynamic> toFirestore() => {
    'patientId': patientId,
    'medicineId': medicineId,
    'scheduledAt': Timestamp.fromDate(scheduledAt),
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'takenAt': takenAt == null ? null : Timestamp.fromDate(takenAt!),
    'actedAt': actedAt == null ? null : Timestamp.fromDate(actedAt!),
    'snoozedUntil': snoozedUntil == null
        ? null
        : Timestamp.fromDate(snoozedUntil!),
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'medicineId': medicineId,
    'scheduledAt': scheduledAt.toIso8601String(),
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'takenAt': takenAt?.toIso8601String(),
    'actedAt': actedAt?.toIso8601String(),
    'snoozedUntil': snoozedUntil?.toIso8601String(),
  };

  factory ScheduledDose.fromFirestore(String id, Map<String, dynamic> data) =>
      ScheduledDose(
        id: id,
        patientId: data['patientId'] as String,
        medicineId: data['medicineId'] as String,
        scheduledAt: _readDate(data['scheduledAt']),
        status: data['status'] as String,
        createdAt: _readDate(data['createdAt']),
        takenAt: data['takenAt'] == null ? null : _readDate(data['takenAt']),
        actedAt: data['actedAt'] == null ? null : _readDate(data['actedAt']),
        snoozedUntil: data['snoozedUntil'] == null
            ? null
            : _readDate(data['snoozedUntil']),
      );

  factory ScheduledDose.fromJson(Map<String, dynamic> data) =>
      ScheduledDose.fromFirestore(data['id'] as String, data);

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }
}
