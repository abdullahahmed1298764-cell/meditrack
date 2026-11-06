import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/patient_profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../utils/validators.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _genderController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  bool _loading = true;

  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = context.read<AppAuthProvider>().appUser!.uid;
    final profile = await _firestoreService.fetchPatientProfile(uid);
    if (profile != null) {
      _ageController.text = profile.age.toString();
      _genderController.text = profile.gender;
      _phoneController.text = profile.phone;
      _emergencyNameController.text = profile.emergencyContactName;
      _emergencyPhoneController.text = profile.emergencyContactPhone;
    }
    setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = context.read<AppAuthProvider>().appUser!.uid;
    final profile = PatientProfile(
      uid: uid,
      age: int.parse(_ageController.text),
      gender: _genderController.text.trim(),
      phone: _phoneController.text.trim(),
      emergencyContactName: _emergencyNameController.text.trim(),
      emergencyContactPhone: _emergencyPhoneController.text.trim(),
    );

    await _firestoreService.savePatientProfile(uid, profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Age'),
                      validator: AppValidators.validateAge,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _genderController,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      validator: (value) => AppValidators.validateRequired(value, fieldName: 'Gender'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Contact number'),
                      validator: AppValidators.validatePhone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emergencyNameController,
                      decoration: const InputDecoration(labelText: 'Emergency contact name'),
                      validator: (value) => AppValidators.validateRequired(value, fieldName: 'Emergency contact name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emergencyPhoneController,
                      decoration: const InputDecoration(labelText: 'Emergency contact phone'),
                      validator: AppValidators.validatePhone,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.save),
                        label: const Text('Save profile'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
