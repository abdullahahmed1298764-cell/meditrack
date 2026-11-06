import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/medical_document.dart';
import '../../models/medical_record.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../utils/validators.dart';

class RecordFormScreen extends StatefulWidget {
  final MedicalRecord? record;

  const RecordFormScreen({super.key, this.record});

  @override
  State<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends State<RecordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final _doctorController = TextEditingController();
  final _reasonController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _prescriptionController = TextEditingController();
  DateTime _visitDate = DateTime.now();
  bool _saving = false;
  late final String _recordId;
  final List<MedicalDocument> _documents = [];

  @override
  void initState() {
    super.initState();
    _recordId = widget.record?.recordId ?? const Uuid().v4();
    if (widget.record != null) {
      final record = widget.record!;
      _doctorController.text = record.doctorOrHospital;
      _reasonController.text = record.reason;
      _diagnosisController.text = record.diagnosis;
      _prescriptionController.text = record.prescription;
      _visitDate = record.visitDate;
    }
  }

  Future<void> _pickAndUploadDocument() async {
    final auth = context.read<AppAuthProvider>();
    final patientId = auth.appUser!.uid;

    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final doc = await _storageService.uploadDocumentForRecord(
        patientId: patientId,
        recordId: _recordId,
        userId: auth.appUser!.uid,
      );
      if (doc != null) {
        if (!mounted) return;
        setState(() => _documents.add(doc));
        messenger?.showSnackBar(
          SnackBar(content: Text('Uploaded ${doc.fileName}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AppAuthProvider>();
    final patientId = auth.appUser!.uid;

    setState(() => _saving = true);

    final record = MedicalRecord(
      recordId: _recordId,
      patientId: patientId,
      doctorOrHospital: _doctorController.text.trim(),
      visitDate: _visitDate,
      reason: _reasonController.text.trim(),
      diagnosis: _diagnosisController.text.trim(),
      prescription: _prescriptionController.text.trim(),
      addedBy: auth.appUser!.uid,
      createdAt: DateTime.now(),
    );

    try {
      if (widget.record == null) {
        await _firestoreService.addRecord(record);
      } else {
        await _firestoreService.updateRecord(record);
      }
      for (final doc in _documents) {
        await _firestoreService.saveDocument(doc);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save record: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.record == null ? 'Add medical record' : 'Edit record',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _doctorController,
                decoration: const InputDecoration(
                  labelText: 'Doctor / Hospital name',
                ),
                validator: (value) => AppValidators.validateRequired(
                  value,
                  fieldName: 'Doctor or hospital',
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _visitDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) {
                    setState(() => _visitDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date of visit'),
                  child: Text(_visitDate.toLocal().toString().split(' ')[0]),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for visit',
                ),
                validator: (value) =>
                    AppValidators.validateRequired(value, fieldName: 'Reason'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _diagnosisController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Diagnosis'),
                validator: (value) => AppValidators.validateRequired(
                  value,
                  fieldName: 'Diagnosis',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prescriptionController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Prescription details',
                ),
                validator: (value) => AppValidators.validateRequired(
                  value,
                  fieldName: 'Prescription',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickAndUploadDocument,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach file'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_documents.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _documents
                      .map((doc) => Chip(label: Text(doc.fileName)))
                      .toList(),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveRecord,
                  icon: const Icon(Icons.save),
                  label: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
