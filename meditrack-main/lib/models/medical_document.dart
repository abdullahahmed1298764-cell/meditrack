import 'package:cloud_firestore/cloud_firestore.dart';

class MedicalDocument {
  final String documentId;
  final String recordId;
  final String patientId;
  final String fileName;
  final String fileUrl;
  final String filePath;
  final String fileType;
  final String reportTitle;
  final String reportCategory;
  final String doctorName;
  final String hospitalName;
  final DateTime reportDate;
  final String description;
  final DateTime uploadedAt;

  MedicalDocument({
    required this.documentId,
    required this.recordId,
    required this.patientId,
    required this.fileName,
    this.fileUrl = '',
    this.filePath = '',
    required this.fileType,
    String? reportTitle,
    this.reportCategory = 'Other medical documents',
    this.doctorName = '',
    this.hospitalName = '',
    DateTime? reportDate,
    this.description = '',
    required this.uploadedAt,
  }) : reportTitle = reportTitle ?? fileName,
       reportDate = reportDate ?? uploadedAt;

  factory MedicalDocument.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return MedicalDocument(
      documentId: documentId,
      recordId: (data['recordId'] ?? data['medical_record_id'] ?? '').toString(),
      patientId: (data['patientId'] ?? data['patient_id'] ?? '').toString(),
      fileName: (data['fileName'] ?? data['file_name'] ?? '').toString(),
      fileUrl: (data['fileUrl'] ?? data['downloadUrl'] ?? '').toString(),
      filePath: (data['filePath'] ?? data['file_path'] ?? '').toString(),
      fileType: (data['fileType'] ?? data['file_type'] ?? '').toString().toLowerCase(),
      reportTitle: (data['reportTitle'] ?? data['report_title'] ?? data['fileName'] ?? '').toString(),
      reportCategory: (data['reportCategory'] ?? data['report_category'] ?? 'Other medical documents')
          .toString(),
      doctorName: (data['doctorName'] ?? data['doctor_name'] ?? '').toString(),
      hospitalName: (data['hospitalName'] ?? data['hospital_name'] ?? '').toString(),
      reportDate: _readDate(data['reportDate'] ?? data['report_date'] ?? data['uploadedAt']),
      description: (data['description'] ?? '').toString(),
      uploadedAt: _readDate(data['uploadedAt'] ?? data['uploaded_at']),
    );
  }

  factory MedicalDocument.fromApiJson(Map<String, dynamic> data) {
    final id = (data['documentId'] ?? data['reportId'] ?? data['report_id'] ?? '').toString();
    return MedicalDocument.fromMap(id, data);
  }

  MedicalDocument copyWith({
    String? documentId,
    String? recordId,
    String? patientId,
    String? fileName,
    String? fileUrl,
    String? filePath,
    String? fileType,
    String? reportTitle,
    String? reportCategory,
    String? doctorName,
    String? hospitalName,
    DateTime? reportDate,
    String? description,
    DateTime? uploadedAt,
  }) {
    return MedicalDocument(
      documentId: documentId ?? this.documentId,
      recordId: recordId ?? this.recordId,
      patientId: patientId ?? this.patientId,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      reportTitle: reportTitle ?? this.reportTitle,
      reportCategory: reportCategory ?? this.reportCategory,
      doctorName: doctorName ?? this.doctorName,
      hospitalName: hospitalName ?? this.hospitalName,
      reportDate: reportDate ?? this.reportDate,
      description: description ?? this.description,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'patientId': patientId,
    'fileName': fileName,
    'fileUrl': fileUrl,
    'filePath': filePath,
    'fileType': fileType,
    'reportTitle': reportTitle,
    'reportCategory': reportCategory,
    'doctorName': doctorName,
    'hospitalName': hospitalName,
    'reportDate': reportDate.toIso8601String(),
    'description': description,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  Map<String, dynamic> toApiJson() => toJson();

  Map<String, dynamic> toMap() {
    return {
      'recordId': recordId,
      'patientId': patientId,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'filePath': filePath,
      'fileType': fileType,
      'reportTitle': reportTitle,
      'reportCategory': reportCategory,
      'doctorName': doctorName,
      'hospitalName': hospitalName,
      'reportDate': Timestamp.fromDate(reportDate),
      'description': description,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
    };
  }

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
