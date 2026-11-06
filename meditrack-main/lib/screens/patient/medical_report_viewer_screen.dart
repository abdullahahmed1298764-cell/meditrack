import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/medical_document.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';

class MedicalReportViewerScreen extends StatefulWidget {
  const MedicalReportViewerScreen({
    super.key,
    required this.report,
  });

  final MedicalDocument report;

  @override
  State<MedicalReportViewerScreen> createState() =>
      _MedicalReportViewerScreenState();
}

class _MedicalReportViewerScreenState extends State<MedicalReportViewerScreen> {
  final _storage = StorageService();
  final _firestore = FirestoreService();
  late Future<Uint8List> _bytes;
  bool _downloading = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _bytes = _storage.downloadDocument(widget.report);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report?'),
        content: Text('“${widget.report.reportTitle}” will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      if (widget.report.fileUrl.contains('/api/reports') || await ReportApiService().isBackendAvailable()) {
        try {
          await ReportApiService().deleteReport(widget.report.documentId);
        } catch (_) {}
      }
      await _storage.deleteDocumentFile(widget.report);
      await _firestore.deleteDocument(widget.report.documentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report deleted successfully.')),
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _bytes;
      final extension = widget.report.fileType.toLowerCase();
      final mimeType = switch (extension) {
        'pdf' => MimeType.pdf,
        'jpg' || 'jpeg' => MimeType.jpeg,
        'png' => MimeType.png,
        _ => MimeType.other,
      };
      final path = await FileSaver.instance.saveFile(
        name: _safeName(widget.report.reportTitle),
        bytes: bytes,
        fileExtension: extension,
        mimeType: mimeType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report saved: $path')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to download report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return Scaffold(
      appBar: AppBar(
        title: Text(report.reportTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Download report',
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Delete report',
            onPressed: _deleting ? null : _delete,
            icon: _deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _errorState(snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Expanded(
                child: report.fileType.toLowerCase() == 'pdf'
                    ? SfPdfViewer.memory(
                        snapshot.data!,
                      )
                    : InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 6,
                        child: Center(
                          child: Image.memory(
                            snapshot.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => _errorState(
                              'This image could not be displayed.',
                            ),
                          ),
                        ),
                      ),
              ),
              _reportDetails(),
            ],
          );
        },
      ),
    );
  }

  Widget _reportDetails() {
    final report = widget.report;
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ExpansionTile(
          title: const Text('Report details'),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            _detailRow('Category', report.reportCategory),
            _detailRow('Report date', DateFormat.yMMMd().format(report.reportDate)),
            _detailRow('Uploaded', DateFormat.yMMMd().format(report.uploadedAt)),
            if (report.doctorName.isNotEmpty)
              _detailRow('Doctor', report.doctorName),
            if (report.hospitalName.isNotEmpty)
              _detailRow('Hospital', report.hospitalName),
            if (report.description.isNotEmpty)
              _detailRow('Notes', report.description),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _errorState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(
                  () => _bytes = _storage.downloadDocument(widget.report),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  String _safeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return cleaned.isEmpty ? 'medical-report' : cleaned;
  }
}
