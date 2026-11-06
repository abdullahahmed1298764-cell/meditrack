import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/medical_record.dart';
import '../../services/firestore_service.dart';
import '../patient/record_detail_screen.dart';

class DoctorPatientRecordsScreen extends StatefulWidget {
  const DoctorPatientRecordsScreen({required this.patient, super.key});

  final AppUser patient;

  @override
  State<DoctorPatientRecordsScreen> createState() =>
      _DoctorPatientRecordsScreenState();
}

class _DoctorPatientRecordsScreenState
    extends State<DoctorPatientRecordsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<MedicalRecord> _records = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _firestoreService.fetchRecordsForPatient(
        widget.patient.uid,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load this patient’s reports: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.patient.name} · Reports')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorState()
          : _records.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _loadRecords,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xffeaf6f8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(widget.patient.name),
                      subtitle: Text(
                        '${widget.patient.email}\n'
                        'Account: ${widget.patient.isActive ? 'Active' : 'Inactive'}'
                        '  ·  ${_records.length} ${_records.length == 1 ? 'report' : 'reports'}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Medical reports',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final record in _records) _recordCard(record),
                ],
              ),
            ),
    );
  }

  Widget _recordCard(MedicalRecord record) {
    final diagnosis = record.diagnosis.trim();
    final prescription = record.prescription.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: const CircleAvatar(
          backgroundColor: Color(0xffeaf6f8),
          child: Icon(Icons.description_outlined, color: Color(0xff087e8b)),
        ),
        title: Text(
          record.reason.isEmpty ? 'Medical visit' : record.reason,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateFormat.yMMMd().format(record.visitDate)}'
                '  ·  ${record.doctorOrHospital}',
              ),
              if (diagnosis.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  'Diagnosis: $diagnosis',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (prescription.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Prescription: $prescription',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecordDetailScreen(
              record: record,
              allowReportUpload: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 44,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          Text(
            'No medical reports yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Reports added by this patient will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
            onPressed: _loadRecords,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
