import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../../utils/validators.dart';

class AddDoctorScreen extends StatefulWidget {
  const AddDoctorScreen({super.key});

  @override
  State<AddDoctorScreen> createState() => _AddDoctorScreenState();
}

class _AddDoctorScreenState extends State<AddDoctorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _emailController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _specialtyController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveDoctor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final doctorId = await _firestoreService.createDoctorProfile(
        name: _nameController.text,
        specialty: _specialtyController.text,
        email: _emailController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor profile saved successfully.')),
      );
      Navigator.pop(context, doctorId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save doctor profile: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Doctor')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: "Doctor's full name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => AppValidators.validateRequired(
                  value,
                  fieldName: "Doctor's full name",
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _specialtyController,
                enabled: !_saving,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Specialty',
                  hintText: 'e.g., Cardiologist',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                ),
                validator: (value) => AppValidators.validateRequired(
                  value,
                  fieldName: 'Specialty',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                enabled: !_saving,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                maxLength: 254,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: AppValidators.validateEmail,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveDoctor,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save Doctor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
