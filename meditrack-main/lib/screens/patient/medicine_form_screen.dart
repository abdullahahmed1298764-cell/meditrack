import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/medicine.dart';
import '../../services/medicine_reminder_service.dart';

class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({required this.patientId, this.medicine, super.key});

  final String patientId;
  final Medicine? medicine;

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _notesController = TextEditingController();
  final _service = MedicineReminderService();
  late DateTime _startDate;
  late DateTime _endDate;
  late String _frequency;
  late String _selectedInstruction;
  late List<TimeOfDay> _times;
  bool _saving = false;

  static const _frequencies = [
    'Once daily',
    'Twice daily',
    'Three times daily',
    'Custom',
  ];
  static const _instructionOptions = [
    'Before food',
    'After food',
    'As prescribed',
  ];

  @override
  void initState() {
    super.initState();
    final medicine = widget.medicine;
    _nameController.text = medicine?.name ?? '';
    _dosageController.text = medicine?.dosage ?? '';
    _notesController.text = medicine?.notes ?? '';
    _startDate = medicine?.startDate ?? DateTime.now();
    _endDate =
        medicine?.endDate ?? DateTime.now().add(const Duration(days: 30));
    _frequency = medicine?.frequency ?? _frequencies.first;
    _selectedInstruction = medicine?.instructions ?? _instructionOptions.last;
    _times = medicine == null
        ? [const TimeOfDay(hour: 8, minute: 0)]
        : medicine.reminderTimes.map(_parseTime).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.medicine != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit medicine' : 'Add medicine')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Medicine details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Medicine name',
                  hintText: 'e.g., Medicine name',
                  prefixIcon: Icon(Icons.medication_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a medicine name.'
                    : null,
              ),
              TextFormField(
                controller: _dosageController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Dosage',
                  hintText: 'e.g., 1 tablet or 5 ml',
                  prefixIcon: Icon(Icons.local_hospital_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the prescribed dosage.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  prefixIcon: Icon(Icons.repeat),
                ),
                items: _frequencies
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _frequency = value;
                    if (value != 'Custom') _times = _defaultTimes(value);
                  });
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reminder times',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addTime,
                    icon: const Icon(Icons.add),
                    label: const Text('Add time'),
                  ),
                ],
              ),
              if (_times.isEmpty)
                const Text(
                  'Add at least one reminder time.',
                  style: TextStyle(color: Colors.red),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _times.length; index++)
                    InputChip(
                      label: Text(_times[index].format(context)),
                      onPressed: () => _selectTime(index),
                      onDeleted: _times.length == 1
                          ? null
                          : () => setState(() => _times.removeAt(index)),
                    ),
                ],
              ),
              if (_frequency != 'Custom')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Choose exactly ${_frequency == 'Once daily'
                        ? 1
                        : _frequency == 'Twice daily'
                        ? 2
                        : 3} time${_frequency == 'Once daily' ? '' : 's'} for this frequency.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _dateField('Start date', _startDate, true)),
                  const SizedBox(width: 12),
                  Expanded(child: _dateField('End date', _endDate, false)),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _selectedInstruction,
                decoration: const InputDecoration(
                  labelText: 'Instructions',
                  prefixIcon: Icon(Icons.restaurant_outlined),
                ),
                items: _instructionOptions
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedInstruction = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional notes (optional)',
                  hintText: 'Add a note about this schedule',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(isEditing ? 'Save changes' : 'Add medicine'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime date, bool isStart) {
    return OutlinedButton(
      onPressed: () => _selectDate(isStart),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 5),
          Text(DateFormat.yMMMd().format(date)),
        ],
      ),
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _startDate = selected;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = selected;
      }
    });
  }

  Future<void> _selectTime(int index) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (selected == null) return;
    setState(() {
      _times[index] = selected;
      _times.sort(_compareTimes);
    });
  }

  Future<void> _addTime() async {
    if (_times.length >= 24) {
      _message('A medicine can have at most 24 reminder times per day.');
      return;
    }
    final selected = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (selected == null) return;
    if (_times.any((time) => _compareTimes(time, selected) == 0)) {
      _message('That reminder time is already listed.');
      return;
    }
    setState(() {
      _frequency = 'Custom';
      _times.add(selected);
      _times.sort(_compareTimes);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final expectedCount = switch (_frequency) {
      'Once daily' => 1,
      'Twice daily' => 2,
      'Three times daily' => 3,
      _ => null,
    };
    if (_times.isEmpty ||
        _times.toSet().length != _times.length ||
        (expectedCount != null && _times.length != expectedCount)) {
      _message('Check the number of unique reminder times for this frequency.');
      return;
    }
    if (_endDate.isBefore(_startDate)) {
      _message('End date cannot be before start date.');
      return;
    }

    setState(() => _saving = true);
    try {
      final old = widget.medicine;
      await _service.saveMedicine(
        Medicine(
          id: old?.id ?? '',
          patientId: widget.patientId,
          name: _nameController.text,
          dosage: _dosageController.text,
          frequency: _frequency,
          reminderTimes: _times.map(_formatTime).toList(),
          startDate: _startDate,
          endDate: _endDate,
          instructions: _selectedInstruction,
          notes: _notesController.text,
          status: old?.status ?? 'active',
          createdAt: old?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static List<TimeOfDay> _defaultTimes(String frequency) => switch (frequency) {
    'Twice daily' => const [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 20, minute: 0),
    ],
    'Three times daily' => const [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 14, minute: 0),
      TimeOfDay(hour: 20, minute: 0),
    ],
    _ => const [TimeOfDay(hour: 8, minute: 0)],
  };

  static TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static int _compareTimes(TimeOfDay first, TimeOfDay second) =>
      first.hour * 60 + first.minute - second.hour * 60 - second.minute;
}
