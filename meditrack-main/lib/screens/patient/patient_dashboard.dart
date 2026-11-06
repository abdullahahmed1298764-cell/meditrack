import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/medical_record.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import 'profile_screen.dart';
import 'medicine_reminder_screen.dart';
import 'record_detail_screen.dart';
import 'record_form_screen.dart';
import 'medical_reports_screen.dart';
import 'record_access_screen.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final FirestoreService _firestoreService = FirestoreService();
  List<MedicalRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final auth = context.read<AppAuthProvider>();
    final patientId = auth.appUser?.uid;

    if (patientId == null) {
      setState(() {
        _records = const [];
        _loading = false;
      });
      return;
    }

    try {
      final records = await _firestoreService.fetchRecordsForPatient(patientId);
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _records = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${auth.appUser?.name ?? 'Patient'}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      _dashboardCard(
                        title: 'My Profile',
                        subtitle: 'View and edit details',
                        icon: Icons.person,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        ).then((_) => _loadRecords()),
                      ),
                      _dashboardCard(
                        title: 'Add Record',
                        subtitle: 'Medical visit summary',
                        icon: Icons.note_add,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RecordFormScreen(),
                          ),
                        ).then((_) => _loadRecords()),
                      ),
                      _dashboardCard(
                        title: 'Medicine Reminders',
                        subtitle: 'Manage doses and history',
                        icon: Icons.medication_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MedicineReminderScreen(),
                          ),
                        ),
                      ),
                      _dashboardCard(
                        title: 'Medical Reports',
                        subtitle: 'Upload and organize files',
                        icon: Icons.folder_copy_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MedicalReportsScreen(),
                          ),
                        ),
                      ),
                      _dashboardCard(
                        title: 'Record Access',
                        subtitle: 'Manage doctor permissions',
                        icon: Icons.verified_user_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RecordAccessScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Medical History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_records.length} records',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_records.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No records yet. Add your first visit summary. ',
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _records.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final record = _records[index];
                        return Card(
                          child: ListTile(
                            title: Text(record.doctorOrHospital),
                            subtitle: Text(
                              '${record.reason} • ${record.visitDate.toLocal().toString().split(' ')[0]}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RecordDetailScreen(record: record),
                              ),
                            ).then((_) => _loadRecords()),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
