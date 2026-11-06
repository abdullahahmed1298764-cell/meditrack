import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medical_document.dart';

class ReportApiService {
  static final ReportApiService _instance = ReportApiService._internal();
  factory ReportApiService() => _instance;
  ReportApiService._internal();

  static const String _tokenPrefKey = 'flask_jwt_token';
  static const String _customHostPrefKey = 'flask_api_host';

  String? _token;

  String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:5000/api';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:5000/api';
      }
    } catch (_) {}
    return 'http://127.0.0.1:5000/api';
  }

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final customHost = prefs.getString(_customHostPrefKey);
    if (customHost != null && customHost.trim().isNotEmpty) {
      return customHost.trim();
    }
    return defaultBaseUrl;
  }

  Future<void> setCustomBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customHostPrefKey, url.trim());
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenPrefKey);
    } else {
      await prefs.setString(_tokenPrefKey, token);
    }
  }

  Future<String?> getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenPrefKey);
    return _token;
  }

  Future<Map<String, String>> _authHeaders({bool isJson = true}) async {
    final token = await getToken();
    final headers = <String, String>{};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Quickly probe if the Flask backend is reachable.
  Future<bool> isBackendAvailable() async {
    try {
      final base = await getBaseUrl();
      final uri = Uri.parse('$base/health');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Upload medical report with multipart request.
  Future<MedicalDocument> uploadReport({
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
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports');
    final request = http.MultipartRequest('POST', uri);

    final headers = await _authHeaders(isJson: false);
    request.headers.addAll(headers);

    request.fields['report_title'] = reportTitle;
    request.fields['report_category'] = reportCategory;
    request.fields['doctor_name'] = doctorName;
    request.fields['hospital_name'] = hospitalName;
    request.fields['description'] = description;
    if (reportDate != null) {
      request.fields['report_date'] = reportDate.toIso8601String();
    }
    if (medicalRecordId != null && medicalRecordId.isNotEmpty) {
      request.fields['medical_record_id'] = medicalRecordId;
    }

    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
    );
    request.files.add(multipartFile);

    onProgress?.call(0.2);
    final streamedResponse = await request.send();
    onProgress?.call(0.8);

    final response = await http.Response.fromStream(streamedResponse);
    onProgress?.call(1.0);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final reportData = body['report'] as Map<String, dynamic>;
      return MedicalDocument.fromApiJson(reportData);
    } else {
      String errorMsg = 'Failed to upload report (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) {
          errorMsg = body['error'].toString();
        }
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  /// List reports with smart search and filter parameters.
  Future<List<MedicalDocument>> fetchReports({
    String? patientId,
    String? category,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    bool newestFirst = true,
    String? medicalRecordId,
  }) async {
    final base = await getBaseUrl();
    final queryParams = <String, String>{};

    if (patientId != null && patientId.isNotEmpty) {
      queryParams['patient_id'] = patientId;
    }
    if (category != null && category.isNotEmpty && category != 'All reports') {
      queryParams['category'] = category;
    }
    if (search != null && search.trim().isNotEmpty) {
      queryParams['search'] = search.trim();
    }
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['end_date'] = endDate.toIso8601String();
    }
    queryParams['sort'] = newestFirst ? 'newest' : 'oldest';
    if (medicalRecordId != null && medicalRecordId.isNotEmpty) {
      queryParams['medical_record_id'] = medicalRecordId;
    }

    final uri = Uri.parse('$base/reports').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['reports'] as List? ?? []);
      return list.map((item) => MedicalDocument.fromApiJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to load reports: ${res.statusCode} ${res.body}');
    }
  }

  /// Retrieve single report details.
  Future<MedicalDocument?> fetchReportById(String reportId) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports/$reportId');
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return MedicalDocument.fromApiJson(body['report'] as Map<String, dynamic>);
    } else if (res.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to fetch report ($reportId): ${res.statusCode}');
    }
  }

  /// Retrieve reports linked to a medical history record.
  Future<List<MedicalDocument>> fetchReportsForRecord(String recordId) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/records/$recordId/reports');
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['reports'] as List? ?? []);
      return list.map((item) => MedicalDocument.fromApiJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to fetch record reports: ${res.statusCode}');
    }
  }

  /// Download binary bytes of a medical report.
  Future<Uint8List> downloadReportBytes(String reportId) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports/$reportId/download');
    final headers = await _authHeaders(isJson: false);
    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 200) {
      return res.bodyBytes;
    } else {
      throw Exception('Failed to download report: ${res.statusCode}');
    }
  }

  /// Update report metadata.
  Future<void> updateReport(MedicalDocument report) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports/${report.documentId}');
    final headers = await _authHeaders();
    final res = await http.put(
      uri,
      headers: headers,
      body: jsonEncode({
        'reportTitle': report.reportTitle,
        'reportCategory': report.reportCategory,
        'doctorName': report.doctorName,
        'hospitalName': report.hospitalName,
        'reportDate': report.reportDate.toIso8601String(),
        'description': report.description,
        'medicalRecordId': report.recordId.isEmpty ? null : report.recordId,
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to update report: ${res.statusCode} ${res.body}');
    }
  }

  /// Delete a report and its underlying file.
  Future<void> deleteReport(String reportId) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports/$reportId');
    final headers = await _authHeaders();
    final res = await http.delete(uri, headers: headers);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to delete report: ${res.statusCode}');
    }
  }

  /// Doctor access permissions via backend.
  Future<void> grantDoctorAccess(String doctorId) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/auth/grant-access');
    final headers = await _authHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'doctorId': doctorId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to grant doctor access: ${res.body}');
    }
  }

  Future<void> revokeDoctorAccess(String doctorId) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/auth/revoke-access');
    final headers = await _authHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'doctorId': doctorId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to revoke doctor access: ${res.body}');
    }
  }
}
