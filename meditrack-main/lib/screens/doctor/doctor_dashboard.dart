import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import 'doctor_patient_records_screen.dart';

class DoctorDashboard extends StatefulWidget {
  const DoctorDashboard({super.key});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  List<AppUser> _patients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshPatients();
  }

  Future<void> _refreshPatients() async {
    final doctorId = context.read<AppAuthProvider>().appUser!.uid;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sharedPatients = await _firestoreService
          .fetchPatientsSharedWithDoctor(doctorId);
      final query = _searchController.text.trim().toLowerCase();
      final results = sharedPatients
          .where(
            (patient) =>
                query.isEmpty ||
                patient.name.toLowerCase().contains(query) ||
                patient.email.toLowerCase().contains(query),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _patients = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load patients: $error';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Show account ID',
            icon: const Icon(Icons.badge_outlined),
            onPressed: () async {
              final uid = auth.appUser!.uid;
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Your doctor account ID'),
                  content: SelectableText(uid),
                  actions: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: uid));
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy ID'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => auth.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search patients who shared records with you',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _refreshPatients,
                ),
              ),
              onSubmitted: (_) => _refreshPatients(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _refreshPatients,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _patients.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? 'No patients have shared their medical records with you.'
                            : 'No patients match your search.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _patients.length,
                      itemBuilder: (context, index) {
                        final patient = _patients[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(patient.name),
                            subtitle: Text(
                              '${patient.email}\n'
                              'Account status: ${patient.isActive ? 'Active' : 'Inactive'}'
                              '\nTap to view medical reports and details',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DoctorPatientRecordsScreen(
                                  patient: patient,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
