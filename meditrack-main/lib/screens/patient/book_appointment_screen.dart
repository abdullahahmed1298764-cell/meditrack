import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import '../../models/appointment.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../utils/validators.dart';

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _doctorEmailController = TextEditingController();
  final _firestoreService = FirestoreService();
  late DateTime _selectedDate;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _selectedDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _doctorEmailController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedDate = DateUtils.dateOnly(selected);
    });
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedTime = selected);
  }

  Future<void> _requestAppointment() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AppAuthProvider>();
    final firebaseUserId =
        Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    final patientId = firebaseUserId ?? auth.appUser?.uid;
    if (patientId == null || patientId.isEmpty) {
      _showMessage('Sign in before requesting an appointment.');
      return;
    }

    final appointmentDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    setState(() => _submitting = true);
    try {
      final doctor = await _firestoreService.findUserByEmail(
        _doctorEmailController.text,
      );
      if (!mounted) return;
      if (doctor == null) {
        _showMessage(
          'Doctor not found. Please check the email and try again.',
          isError: true,
        );
        return;
      }

      await _firestoreService.requestAppointment(
        Appointment(
          id: const Uuid().v4(),
          patientId: patientId,
          patientName: auth.appUser?.name.trim().isNotEmpty == true
              ? auth.appUser!.name.trim()
              : 'Patient',
          doctorId: doctor.uid,
          dateTime: appointmentDateTime,
          status: 'pending',
          reason: _reasonController.text.trim(),
          doctorName: doctor.name,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment request sent.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Unable to request appointment: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Appointment')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                "Enter the doctor's email and appointment time",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _doctorEmailController,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                maxLength: 254,
                decoration: const InputDecoration(
                  labelText: "Doctor's email address",
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: AppValidators.validateEmail,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _selectDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(DateFormat.yMMMd().format(_selectedDate)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _selectTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(_selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonController,
                enabled: !_submitting,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason for visit',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.edit_note_outlined),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a reason for your visit.'
                    : null,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _requestAppointment,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(
                    _submitting ? 'Sending request...' : 'Request Appointment',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
