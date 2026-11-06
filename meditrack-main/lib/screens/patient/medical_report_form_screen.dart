import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/medical_document.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';

const medicalReportCategories = <String>[
  'Blood Test',
  'Urine Test',
  'X-ray',
  'MRI Scan',
  'CT Scan',
  'Prescription',
  'Other medical documents',
];

class MedicalReportFormScreen extends StatefulWidget {
  const MedicalReportFormScreen({
    super.key,
    this.report,
    this.medicalRecordId = '',
  });

  final MedicalDocument? report;
  final String medicalRecordId;

  @override
  State<MedicalReportFormScreen> createState() =>
      _MedicalReportFormScreenState();
}

class _MedicalReportFormScreenState extends State<MedicalReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storage = StorageService();
  final _firestore = FirestoreService();
  final _title = TextEditingController();
  final _doctor = TextEditingController();
  final _hospital = TextEditingController();
  final _description = TextEditingController();
  String _category = medicalReportCategories.first;
  DateTime _reportDate = DateTime.now();
  String? _fileName;
  String? _extension;
  Uint8List? _bytes;
  double? _uploadProgress;
  bool _saving = false;

  bool get _editing => widget.report != null;

  @override
  void initState() {
    super.initState();
    final report = widget.report;
    if (report != null) {
      _title.text = report.reportTitle;
      _doctor.text = report.doctorName;
      _hospital.text = report.hospitalName;
      _description.text = report.description;
      _category = medicalReportCategories.contains(report.reportCategory)
          ? report.reportCategory
          : medicalReportCategories.last;
      _reportDate = report.reportDate;
      _fileName = report.fileName;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _doctor.dispose();
    _hospital.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size > 5 * 1024 * 1024) {
      _message('File exceeds the 5 MB limit.');
      return;
    }
    if (file.bytes == null) {
      _message('Unable to read the selected file.');
      return;
    }
    setState(() {
      _fileName = file.name;
      _extension = file.extension?.toLowerCase();
      _bytes = file.bytes;
    });
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date != null) setState(() => _reportDate = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_editing && (_bytes == null || _fileName == null)) {
      _message('Choose a PDF or image report to upload.');
      return;
    }

    final patientId = context.read<AppAuthProvider>().appUser!.uid;
    setState(() {
      _saving = true;
      _uploadProgress = _editing ? null : 0;
    });

    MedicalDocument? uploaded;
    try {
      if (_editing) {
        final previous = widget.report!;
        final updatedDoc = MedicalDocument(
          documentId: previous.documentId,
          recordId: previous.recordId,
          patientId: previous.patientId,
          fileName: previous.fileName,
          fileUrl: previous.fileUrl,
          filePath: previous.filePath,
          fileType: previous.fileType,
          reportTitle: _title.text.trim(),
          reportCategory: _category,
          doctorName: _doctor.text.trim(),
          hospitalName: _hospital.text.trim(),
          reportDate: _reportDate,
          description: _description.text.trim(),
          uploadedAt: previous.uploadedAt,
        );
        try {
          if (await ReportApiService().isBackendAvailable()) {
            await ReportApiService().updateReport(updatedDoc);
          }
        } catch (_) {}
        await _firestore.updateDocument(updatedDoc);
      } else {
        final isApiReady = await ReportApiService().isBackendAvailable();
        if (isApiReady) {
          uploaded = await _storage.uploadDocumentToApi(
            bytes: _bytes!,
            fileName: _fileName!,
            reportTitle: _title.text.trim(),
            reportCategory: _category,
            doctorName: _doctor.text.trim(),
            hospitalName: _hospital.text.trim(),
            reportDate: _reportDate,
            description: _description.text.trim(),
            medicalRecordId: widget.medicalRecordId.isNotEmpty ? widget.medicalRecordId : null,
            onProgress: (progress) {
              if (mounted) setState(() => _uploadProgress = progress);
            },
          );
          await _firestore.saveDocument(uploaded);
        } else {
          uploaded = await _storage.createDocumentForFile(
            patientId: patientId,
            recordId: widget.medicalRecordId,
            fileName: _fileName!,
            extension: _extension ?? '',
            bytes: _bytes!,
            reportTitle: _title.text.trim(),
            reportCategory: _category,
            doctorName: _doctor.text.trim(),
            hospitalName: _hospital.text.trim(),
            reportDate: _reportDate,
            description: _description.text.trim(),
            onProgress: (progress) {
              if (mounted) setState(() => _uploadProgress = progress);
            },
          );
          await _firestore.saveDocument(uploaded);
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (uploaded != null) {
        try {
          await _storage.deleteDocumentFile(uploaded);
        } catch (cleanupError) {
          if (mounted) {
            _message('Report save failed ($error); file cleanup failed ($cleanupError).');
          }
          return;
        }
      }
      if (mounted) _message('Unable to save report: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = null;
        });
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit report' : 'Upload report')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Report title',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Report category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: medicalReportCategories
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _category = value);
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _doctor,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Doctor name',
                prefixIcon: Icon(Icons.medical_services_outlined),
              ),
            ),
            TextFormField(
              controller: _hospital,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Hospital or clinic',
                prefixIcon: Icon(Icons.local_hospital_outlined),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Report date: ${_dateLabel(_reportDate)}'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Description or notes',
                alignLabelWithHint: true,
              ),
            ),
            if (!_editing) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickFile,
                icon: const Icon(Icons.upload_file),
                label: Text(_fileName ?? 'Choose PDF or image (max 5 MB)'),
              ),
              if (_uploadProgress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _uploadProgress),
                const SizedBox(height: 4),
                Text('${(_uploadProgress! * 100).round()}% uploaded'),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text('File: ${widget.report!.fileName}'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_editing ? Icons.save_outlined : Icons.cloud_upload_outlined),
              label: Text(_saving
                  ? (_editing ? 'Saving...' : 'Uploading...')
                  : (_editing ? 'Save changes' : 'Upload report')),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
