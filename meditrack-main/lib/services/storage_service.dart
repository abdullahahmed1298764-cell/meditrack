import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../firebase_options.dart';
import '../models/medical_document.dart';
import 'api_service.dart';

class StorageService {
  FirebaseStorage? _storage;
  final Uuid _uuid = const Uuid();
  final ReportApiService _apiService = ReportApiService();

  StorageService() {
    if (Firebase.apps.isNotEmpty) {
      _storage = FirebaseStorage.instance;
    }
  }

  bool get isDemoMode =>
      Firebase.apps.isEmpty || DefaultFirebaseOptions.isDemoConfig;

  bool get isAvailable => !isDemoMode;

  FirebaseStorage get storage => _storage ?? _throwNoApp();

  FirebaseStorage _throwNoApp() {
    throw FirebaseException(
      plugin: 'firebase_storage',
      code: 'no-app',
      message: 'No Firebase app has been initialized.',
    );
  }

  static Uint8List? readFileBytesForPicker(PlatformFile file) {
    return file.bytes;
  }

  Future<MedicalDocument?> uploadDocumentForRecord({
    required String patientId,
    required String recordId,
    required String userId,
    void Function(double progress)? onProgress,
  }) async {
    if (userId != patientId) {
      throw StateError('Only the patient can upload their own documents.');
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final selectedFile = result.files.first;
    final bytes = readFileBytesForPicker(selectedFile);
    if (bytes == null) {
      throw Exception('Unable to read the selected file.');
    }

    return createDocumentForFile(
      patientId: patientId,
      recordId: recordId,
      fileName: selectedFile.name,
      extension: selectedFile.extension ?? '',
      bytes: bytes,
      onProgress: onProgress,
    );
  }

  Future<MedicalDocument> createDocumentForFile({
    required String patientId,
    required String recordId,
    required String fileName,
    required String extension,
    required Uint8List bytes,
    String? reportTitle,
    String reportCategory = 'Other medical documents',
    String doctorName = '',
    String hospitalName = '',
    DateTime? reportDate,
    String description = '',
    void Function(double progress)? onProgress,
  }) async {
    const maxBytes = 5 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw Exception('File exceeds the 5 MB limit.');
    }

    final normalizedExtension = extension.toLowerCase();
    final contentType = _contentTypeForExtension(normalizedExtension);
    _validateFileSignature(bytes, normalizedExtension);
    final documentId = _uuid.v4();
    final uploadedAt = DateTime.now();
    if (isDemoMode) onProgress?.call(1);
    final filePath = isDemoMode
        ? ''
        : await _uploadToFirebase(
            patientId: patientId,
            recordId: recordId,
            documentId: documentId,
            extension: normalizedExtension,
            bytes: bytes,
            contentType: contentType,
            onProgress: onProgress,
          );

    return MedicalDocument(
      documentId: documentId,
      recordId: recordId,
      patientId: patientId,
      fileName: fileName,
      fileUrl: isDemoMode ? 'data:$contentType;base64,${base64Encode(bytes)}' : '',
      filePath: filePath,
      fileType: normalizedExtension,
      reportTitle: reportTitle,
      reportCategory: reportCategory,
      doctorName: doctorName,
      hospitalName: hospitalName,
      reportDate: reportDate,
      description: description,
      uploadedAt: uploadedAt,
    );
  }

  Future<String> _uploadToFirebase({
    required String patientId,
    required String recordId,
    required String documentId,
    required String extension,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final ref = storage.ref().child(
      'patients/$patientId/reports/$documentId.$extension',
    );
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    await for (final snapshot in uploadTask.snapshotEvents) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    }
    await uploadTask;
    return ref.fullPath;
  }

  Future<Uint8List> downloadDocument(
    MedicalDocument document, {
    int maxSize = 5 * 1024 * 1024,
  }) async {
    if (document.fileUrl.startsWith('data:')) {
      final separator = document.fileUrl.indexOf(',');
      if (separator < 0) throw const FormatException('Invalid local document data.');
      return Uint8List.fromList(
        base64Decode(document.fileUrl.substring(separator + 1)),
      );
    }

    // If served by Flask REST API or connected to backend
    if (document.fileUrl.contains('/api/reports') || document.filePath.contains('uploads')) {
      return await _apiService.downloadReportBytes(document.documentId);
    }

    try {
      if (await _apiService.isBackendAvailable()) {
        return await _apiService.downloadReportBytes(document.documentId);
      }
    } catch (_) {}

    if (isDemoMode) {
      throw StateError('This document is not available in local demo storage.');
    }

    final reference = document.filePath.isNotEmpty
        ? storage.ref().child(document.filePath)
        : storage.refFromURL(document.fileUrl);
    final bytes = await reference.getData(maxSize);
    if (bytes == null) throw StateError('The document file is empty.');
    return bytes;
  }

  Future<void> deleteDocumentFile(MedicalDocument document) async {
    if (document.fileUrl.contains('/api/reports')) {
      try {
        await _apiService.deleteReport(document.documentId);
      } catch (_) {}
      return;
    }
    if (document.filePath.isEmpty && document.fileUrl.isEmpty) return;
    if (document.fileUrl.startsWith('data:')) return;
    if (isDemoMode) return;

    final reference = document.filePath.isNotEmpty
        ? storage.ref().child(document.filePath)
        : storage.refFromURL(document.fileUrl);
    await reference.delete();
  }

  Future<MedicalDocument> uploadDocumentToApi({
    required Uint8List bytes,
    required String fileName,
    required String reportTitle,
    required String reportCategory,
    String doctorName = '',
    String hospitalName = '',
    DateTime? reportDate,
    String description = '',
    String? medicalRecordId,
    void Function(double progress)? onProgress,
  }) async {
    const maxBytes = 5 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw Exception('File exceeds the 5 MB limit.');
    }
    final extension = fileName.split('.').last.toLowerCase();
    _validateFileSignature(bytes, extension);
    return await _apiService.uploadReport(
      bytes: bytes,
      fileName: fileName,
      reportTitle: reportTitle,
      reportCategory: reportCategory,
      doctorName: doctorName,
      hospitalName: hospitalName,
      reportDate: reportDate,
      description: description,
      medicalRecordId: medicalRecordId,
      onProgress: onProgress,
    );
  }

  static String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        throw Exception('Unsupported file type.');
    }
  }

  static void _validateFileSignature(Uint8List bytes, String extension) {
    final valid = switch (extension) {
      'pdf' =>
        bytes.length >= 5 &&
            String.fromCharCodes(bytes.take(5)) == '%PDF-',
      'jpg' || 'jpeg' =>
        bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff,
      'png' =>
        bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4e &&
            bytes[3] == 0x47 &&
            bytes[4] == 0x0d &&
            bytes[5] == 0x0a &&
            bytes[6] == 0x1a &&
            bytes[7] == 0x0a,
      _ => false,
    };
    if (!valid) {
      throw const FormatException(
        'The selected file contents do not match a supported PDF, JPG, JPEG, or PNG file.',
      );
    }
  }
}
