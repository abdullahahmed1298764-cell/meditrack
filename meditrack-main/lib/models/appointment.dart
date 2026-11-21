import 'package:cloud_firestore/cloud_firestore.dart';

class Appointment {
  const Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.dateTime,
    required this.status,
    required this.reason,
    this.doctorName,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final DateTime dateTime;
  final String status;
  final String reason;
  final String? doctorName;

  factory Appointment.fromJson(Map<String, dynamic> data) => Appointment(
    id: (data['id'] ?? '').toString(),
    patientId: (data['patientId'] ?? '').toString(),
    patientName: (data['patientName'] ?? '').toString(),
    doctorId: (data['doctorId'] ?? '').toString(),
    dateTime: _readDate(data['dateTime']),
    status: (data['status'] ?? '').toString(),
    reason: (data['reason'] ?? '').toString(),
    doctorName: data['doctorName']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'patientName': patientName,
    'doctorId': doctorId,
    'dateTime': dateTime.toIso8601String(),
    'status': status,
    'reason': reason,
    'doctorName': doctorName,
  };

  Map<String, dynamic> toFirestore() => {
    'patientId': patientId,
    'patientName': patientName,
    'doctorId': doctorId,
    'dateTime': Timestamp.fromDate(dateTime),
    'status': status,
    'reason': reason,
    if (doctorName != null) 'doctorName': doctorName,
  };

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    throw FormatException('Invalid appointment dateTime: $value');
  }
}
