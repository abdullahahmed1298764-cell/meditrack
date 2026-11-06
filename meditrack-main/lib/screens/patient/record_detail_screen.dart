import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/medical_document.dart';
import '../../models/medical_record.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import 'medical_report_form_screen.dart';
import 'medical_report_viewer_screen.dart';

class RecordDetailScreen extends StatefulWidget {
  final MedicalRecord record;
  final bool allowReportUpload;

  const RecordDetailScreen({
    super.key,
    required this.record,
    this.allowReportUpload = true,
  });

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<MedicalDocument> _documents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      List<MedicalDocument> docs;
      if (await ReportApiService().isBackendAvailable()) {
        try {
          docs = await ReportApiService().fetchReportsForRecord(widget.record.recordId);
          if (docs.isEmpty) {
            docs = await _firestoreService.fetchDocumentsForRecord(
              widget.record.recordId,
              patientId: widget.record.patientId,
            );
          }
        } catch (_) {
          docs = await _firestoreService.fetchDocumentsForRecord(
            widget.record.recordId,
            patientId: widget.record.patientId,
          );
        }
      } else {
        docs = await _firestoreService.fetchDocumentsForRecord(
          widget.record.recordId,
          patientId: widget.record.patientId,
        );
      }
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load attached reports: $error';
        _loading = false;
      });
    }
  }

  Future<void> _addReport() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicalReportFormScreen(
          medicalRecordId: widget.record.recordId,
        ),
      ),
    );
    if (saved == true) _loadDocuments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _infoRow('Doctor / Hospital', widget.record.doctorOrHospital),
          _infoRow('Visit date', DateFormat.yMMMd().format(widget.record.visitDate)),
          _infoRow('Reason', widget.record.reason),
          _infoRow('Diagnosis', widget.record.diagnosis),
          const SizedBox(height: 12),
          const Text(
            'Prescription',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(widget.record.prescription),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Related medical reports',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              if (widget.allowReportUpload)
                IconButton(
                  tooltip: 'Attach a report',
                  onPressed: _addReport,
                  icon: const Icon(Icons.add_circle_outline),
                ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!),
                TextButton(onPressed: _loadDocuments, child: const Text('Retry')),
              ],
            )
          else if (_documents.isEmpty)
            const Text('No reports are linked to this medical history record.')
          else
            ..._documents.map(_documentCard),
        ],
      ),
    );
  }

  Widget _documentCard(MedicalDocument document) => Card(
        child: ListTile(
          leading: Icon(
            document.fileType == 'pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
          ),
          title: Text(document.reportTitle),
          subtitle: Text(
            '${document.reportCategory} · ${DateFormat.yMMMd().format(document.reportDate)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MedicalReportViewerScreen(report: document),
            ),
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value),
          ],
        ),
      );
}
