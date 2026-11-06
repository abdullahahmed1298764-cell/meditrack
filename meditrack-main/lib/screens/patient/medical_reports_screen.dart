import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/medical_document.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import 'medical_report_form_screen.dart';
import 'medical_report_viewer_screen.dart';

class MedicalReportsScreen extends StatefulWidget {
  const MedicalReportsScreen({super.key});

  @override
  State<MedicalReportsScreen> createState() => _MedicalReportsScreenState();
}

class _MedicalReportsScreenState extends State<MedicalReportsScreen> {
  final _firestore = FirestoreService();
  final _storage = StorageService();
  final _search = TextEditingController();
  List<MedicalDocument> _reports = const [];
  String _category = 'All reports';
  DateTimeRange? _dateRange;
  bool _newestFirst = true;
  bool _loading = true;
  bool _backendActive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final patientId = context.read<AppAuthProvider>().appUser?.uid;
    if (patientId == null) {
      setState(() {
        _reports = const [];
        _loading = false;
        _error = 'Sign in as a patient to view reports.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final isBackend = await ReportApiService().isBackendAvailable();
      List<MedicalDocument> reports;
      if (isBackend) {
        reports = await ReportApiService().fetchReports(patientId: patientId);
      } else {
        reports = await _firestore.fetchDocumentsForPatient(patientId);
      }
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _backendActive = isBackend;
        _loading = false;
      });
    } catch (_) {
      try {
        final reports = await _firestore.fetchDocumentsForPatient(patientId);
        if (!mounted) return;
        setState(() {
          _reports = reports;
          _backendActive = false;
          _loading = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _error = 'Unable to load medical reports: $error';
          _loading = false;
        });
      }
    }
  }

  List<MedicalDocument> get _filteredReports {
    final query = _search.text.trim().toLowerCase();
    final reports = _reports.where((report) {
      final matchesText = query.isEmpty ||
          report.reportTitle.toLowerCase().contains(query) ||
          report.doctorName.toLowerCase().contains(query) ||
          report.hospitalName.toLowerCase().contains(query);
      final matchesCategory =
          _category == 'All reports' || report.reportCategory == _category;
      final matchesDate = _dateRange == null ||
          (!report.reportDate.isBefore(_dateRange!.start) &&
              !report.reportDate.isAfter(
                DateTime(
                  _dateRange!.end.year,
                  _dateRange!.end.month,
                  _dateRange!.end.day,
                  23,
                  59,
                  59,
                ),
              ));
      return matchesText && matchesCategory && matchesDate;
    }).toList()
      ..sort((a, b) => _newestFirst
          ? b.reportDate.compareTo(a.reportDate)
          : a.reportDate.compareTo(b.reportDate));
    return reports;
  }

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Future<void> _createReport() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MedicalReportFormScreen()),
    );
    if (saved == true) {
      await _loadReports();
      if (mounted) _message('Medical report uploaded successfully.');
    }
  }

  Future<void> _editReport(MedicalDocument report) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicalReportFormScreen(report: report),
      ),
    );
    if (saved == true) await _loadReports();
  }

  Future<void> _deleteReport(MedicalDocument report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text(
          '“${report.reportTitle}” will be permanently removed from your records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (report.fileUrl.contains('/api/reports') || await ReportApiService().isBackendAvailable()) {
        try {
          await ReportApiService().deleteReport(report.documentId);
        } catch (_) {}
      }
      await _storage.deleteDocumentFile(report);
      await _firestore.deleteDocument(report.documentId);
      await _loadReports();
      if (mounted) _message('Report deleted.');
    } catch (error) {
      if (mounted) _message('Unable to delete report: $error');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reports = _filteredReports;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Medical Reports',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _newestFirst ? 'Sort oldest first' : 'Sort newest first',
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
            icon: const Icon(Icons.swap_vert),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createReport,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload report'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _loadReports,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      // Backend live status indicator banner
                      if (_backendActive)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
                              SizedBox(width: 8),
                              Text(
                                'Flask REST API & MySQL Connected',
                                style: TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      // Search bar
                      TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          hintText: 'Search name, doctor, or hospital',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF0F766E)),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: _search.clear,
                                  icon: const Icon(Icons.clear),
                                ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _categoryFilters(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectDateRange,
                              icon: const Icon(Icons.date_range, size: 18),
                              label: Text(
                                _dateRange == null
                                    ? 'Filter by date'
                                    : '${DateFormat.MMMd().format(_dateRange!.start)} – ${DateFormat.MMMd().format(_dateRange!.end)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          if (_dateRange != null)
                            IconButton(
                              tooltip: 'Clear date filter',
                              onPressed: () => setState(() => _dateRange = null),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${reports.length} ${reports.length == 1 ? 'report' : 'reports'}'
                        '  ·  ${_newestFirst ? 'Newest first' : 'Oldest first'}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 10),
                      if (reports.isEmpty)
                        _emptyState()
                      else
                        ..._buildGroupedReports(reports),
                    ],
                  ),
                ),
    );
  }

  Widget _categoryFilters() => SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            'All reports',
            ...medicalReportCategories,
          ]
              .map(
                (category) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: _category == category,
                    selectedColor: const Color(0xFFCCFBF1),
                    labelStyle: TextStyle(
                      color: _category == category ? const Color(0xFF0F766E) : const Color(0xFF475569),
                      fontWeight: _category == category ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: _category == category ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    onSelected: (_) => setState(() => _category = category),
                  ),
                ),
              )
              .toList(),
        ),
      );

  List<Widget> _buildGroupedReports(List<MedicalDocument> reports) {
    final categories = <String, List<MedicalDocument>>{};
    for (final report in reports) {
      categories.putIfAbsent(report.reportCategory, () => []).add(report);
    }
    return categories.entries.expand((categoryEntry) {
      final months = <String, List<MedicalDocument>>{};
      for (final report in categoryEntry.value) {
        final monthKey =
            '${report.reportDate.year}-${report.reportDate.month.toString().padLeft(2, '0')}';
        months.putIfAbsent(monthKey, () => []).add(report);
      }
      final widgets = <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                categoryEntry.key,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
              ),
            ],
          ),
        ),
      ];
      for (final monthReports in months.values) {
        final date = monthReports.first.reportDate;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4, left: 12),
            child: Text(
              DateFormat.yMMMM().format(date),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF0284C7),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        );
        widgets.addAll(monthReports.map(_reportCard));
      }
      return widgets;
    }).toList();
  }

  IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'blood test':
      case 'blood reports':
        return Icons.water_drop_outlined;
      case 'urine test':
        return Icons.science_outlined;
      case 'x-ray':
      case 'x-ray reports':
        return Icons.document_scanner_outlined;
      case 'mri scan':
        return Icons.radio_button_checked_outlined;
      case 'ct scan':
        return Icons.camera_alt_outlined;
      case 'prescription':
        return Icons.receipt_long_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color _colorForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'blood test':
      case 'blood reports':
        return const Color(0xFFE11D48);
      case 'urine test':
        return const Color(0xFFD97706);
      case 'x-ray':
      case 'x-ray reports':
        return const Color(0xFF0284C7);
      case 'mri scan':
        return const Color(0xFF6366F1);
      case 'ct scan':
        return const Color(0xFF0891B2);
      case 'prescription':
        return const Color(0xFF059669);
      default:
        return const Color(0xFF0F766E);
    }
  }

  Widget _reportCard(MedicalDocument report) {
    final image = report.fileType == 'jpg' ||
        report.fileType == 'jpeg' ||
        report.fileType == 'png';
    final categoryColor = _colorForCategory(report.reportCategory);
    final categoryIcon = _iconForCategory(report.reportCategory);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        leading: CircleAvatar(
          backgroundColor: categoryColor.withValues(alpha: 0.12),
          child: Icon(
            image ? Icons.image_outlined : categoryIcon,
            color: categoryColor,
          ),
        ),
        title: Text(
          report.reportTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (report.doctorName.isNotEmpty) report.doctorName,
                  if (report.hospitalName.isNotEmpty) report.hospitalName,
                ].join(' · ').isEmpty
                    ? DateFormat.yMMMd().format(report.uploadedAt)
                    : '${[
                        if (report.doctorName.isNotEmpty) report.doctorName,
                        if (report.hospitalName.isNotEmpty) report.hospitalName,
                      ].join(' · ')} · ${DateFormat.yMMMd().format(report.uploadedAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: image ? const Color(0xFFE0F2FE) : const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      report.fileType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: image ? const Color(0xFF0284C7) : const Color(0xFFE11D48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Report Date: ${DateFormat.yMMMd().format(report.reportDate)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _editReport(report);
            if (value == 'delete') _deleteReport(report);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit details')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MedicalReportViewerScreen(report: report),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 18),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 44,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _reports.isEmpty ? 'No medical reports yet' : 'No matching reports',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _reports.isEmpty
                  ? 'Upload your blood tests, urine tests, X-rays, MRI scans, CT scans, or prescriptions to keep your healthcare history organized.'
                  : 'Try a different search or clear the selected filters.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            if (_reports.isEmpty) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _createReport,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload report'),
              ),
            ],
          ],
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadReports,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
