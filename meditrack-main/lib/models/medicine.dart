import 'package:cloud_firestore/cloud_firestore.dart';

class Medicine {
  const Medicine({
    required this.id,
    required this.patientId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.reminderTimes,
    required this.startDate,
    required this.endDate,
    required this.instructions,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String patientId;
  final String name;
  final String dosage;
  final String frequency;
  final List<String> reminderTimes;
  final DateTime startDate;
  final DateTime endDate;
  final String instructions;
  final String notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  String statusOn(DateTime date) {
    if (status != 'active') return status;
    if (_dateOnly(endDate).isBefore(_dateOnly(date))) return 'completed';
    return 'active';
  }

  Map<String, dynamic> toFirestore() => {
    'patientId': patientId,
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'reminderTimes': reminderTimes,
    'startDate': Timestamp.fromDate(_dateOnly(startDate)),
    'endDate': Timestamp.fromDate(_dateOnly(endDate)),
    'instructions': instructions,
    'notes': notes,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'reminderTimes': reminderTimes,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'instructions': instructions,
    'notes': notes,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Medicine.fromFirestore(String id, Map<String, dynamic> data) =>
      Medicine(
        id: id,
        patientId: data['patientId'] as String,
        name: data['name'] as String,
        dosage: data['dosage'] as String,
        frequency: data['frequency'] as String,
        reminderTimes: List<String>.from(data['reminderTimes'] as List),
        startDate: _readDate(data['startDate']),
        endDate: _readDate(data['endDate']),
        instructions: (data['instructions'] ?? '') as String,
        notes: (data['notes'] ?? '') as String,
        status: data['status'] as String,
        createdAt: _readDate(data['createdAt']),
        updatedAt: _readDate(data['updatedAt']),
      );

  factory Medicine.fromJson(Map<String, dynamic> data) =>
      Medicine.fromFirestore(data['id'] as String, data);

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
