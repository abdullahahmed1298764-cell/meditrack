import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

class RecordAccessScreen extends StatefulWidget {
  const RecordAccessScreen({super.key});

  @override
  State<RecordAccessScreen> createState() => _RecordAccessScreenState();
}

class _RecordAccessScreenState extends State<RecordAccessScreen> {
  final _firestore = FirestoreService();
  final _doctorId = TextEditingController();
  List<String> _doctorIds = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _doctorId.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    final patientId = context.read<AppAuthProvider>().appUser!.uid;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ids = await _firestore.fetchAuthorizedDoctorIds(patientId);
      if (!mounted) return;
      setState(() {
        _doctorIds = ids;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load sharing settings: $error';
        _loading = false;
      });
    }
  }

  Future<void> _grantAccess() async {
    final doctorId = _doctorId.text.trim();
    if (doctorId.isEmpty) return;
    final patientId = context.read<AppAuthProvider>().appUser!.uid;
    setState(() => _saving = true);
    try {
      await _firestore.grantDoctorAccess(
        patientId: patientId,
        doctorId: doctorId,
      );
      _doctorId.clear();
      await _loadAccess();
      if (mounted) _message('Doctor access granted.');
    } catch (error) {
      if (mounted) _message('Unable to grant access: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revokeAccess(String doctorId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke access?'),
        content: const Text(
          'This doctor will no longer be able to view your medical history or reports.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final patientId = context.read<AppAuthProvider>().appUser!.uid;
    try {
      await _firestore.revokeDoctorAccess(
        patientId: patientId,
        doctorId: doctorId,
      );
      await _loadAccess();
      if (mounted) _message('Doctor access revoked.');
    } catch (error) {
      if (mounted) _message('Unable to revoke access: $error');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Record access')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _loadAccess,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Card(
                        color: const Color(0xffeaf6f8),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Only doctors you authorize can view your medical records and reports. '
                            'Ask your doctor for their account ID. You can revoke access at any time.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _doctorId,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saving ? null : _grantAccess(),
                        decoration: const InputDecoration(
                          labelText: 'Doctor account ID',
                          hintText: 'Paste the doctor’s account ID',
                          prefixIcon: Icon(Icons.person_add_alt_1),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _saving ? null : _grantAccess,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_outlined),
                        label: Text(_saving ? 'Saving...' : 'Grant doctor access'),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Authorized doctors',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_doctorIds.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('You have not shared records with a doctor.'),
                          ),
                        )
                      else
                        ..._doctorIds.map(
                          (id) => Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.medical_services_outlined),
                              ),
                              title: const Text('Doctor account'),
                              subtitle: SelectableText(id),
                              trailing: IconButton(
                                tooltip: 'Revoke access',
                                onPressed: () => _revokeAccess(id),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      );
}
