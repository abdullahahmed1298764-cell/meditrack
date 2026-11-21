import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../firebase_options.dart';
import '../../models/appointment.dart';
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
  late final String _doctorId;
  late final Stream<List<Appointment>> _appointmentsStream;
  late final Stream<List<Appointment>> _pendingAppointmentsStream;
  final Set<String> _updatingAppointmentIds = {};
  int _streamRefreshKey = 0;

  bool get _isDemoMode =>
      Firebase.apps.isEmpty || DefaultFirebaseOptions.isDemoConfig;

  @override
  void initState() {
    super.initState();
    final firebaseUserId =
        Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    _doctorId =
        firebaseUserId ?? context.read<AppAuthProvider>().appUser!.uid;
    _appointmentsStream = _firestoreService.streamDoctorAppointments(_doctorId);
    _pendingAppointmentsStream = _firestoreService
        .streamPendingDoctorAppointments(_doctorId);
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

  void _retryAppointments() {
    setState(() => _streamRefreshKey++);
  }

  Future<void> _updateAppointmentStatus(
    Appointment appointment,
    String status,
  ) async {
    if (!_updatingAppointmentIds.add(appointment.id)) return;
    setState(() {});
    var succeeded = false;
    try {
      await _firestoreService.updateAppointmentStatus(appointment.id, status);
      succeeded = true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update appointment: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingAppointmentIds.remove(appointment.id);
          if (succeeded && _isDemoMode) _streamRefreshKey++;
        });
      }
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Doctor Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Patients'),
              Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Schedule'),
            ],
          ),
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
        body: Column(
          children: [
            _buildActionRequiredSection(),
            Expanded(
              child: TabBarView(
                children: [_buildPatientsTab(), _buildScheduleTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRequiredSection() {
    return StreamBuilder<List<Appointment>>(
      key: ValueKey('pending-$_streamRefreshKey'),
      stream: _pendingAppointmentsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final pendingAppointments = snapshot.data!
            .where(
              (appointment) => appointment.status.toLowerCase() == 'pending',
            )
            .toList();
        if (pendingAppointments.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Action Required',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(
                height: 142,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: pendingAppointments.length,
                  itemBuilder: (context, index) {
                    final appointment = pendingAppointments[index];
                    final isUpdating = _updatingAppointmentIds.contains(
                      appointment.id,
                    );
                    return SizedBox(
                      width: 260,
                      child: Card(
                        margin: const EdgeInsets.all(4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment.patientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.schedule, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      DateFormat.yMMMd().add_jm().format(
                                        appointment.dateTime,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: isUpdating
                                        ? null
                                        : () => _updateAppointmentStatus(
                                            appointment,
                                            'confirmed',
                                          ),
                                    style: TextButton.styleFrom(
                                      minimumSize: Size.zero,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: const Text('Approve'),
                                  ),
                                  TextButton(
                                    onPressed: isUpdating
                                        ? null
                                        : () => _updateAppointmentStatus(
                                            appointment,
                                            'cancelled',
                                          ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      minimumSize: Size.zero,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: const Text('Decline'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPatientsTab() {
    return Padding(
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
                              builder: (_) =>
                                  DoctorPatientRecordsScreen(patient: patient),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTab() {
    return StreamBuilder<List<Appointment>>(
      key: ValueKey('schedule-$_streamRefreshKey'),
      stream: _appointmentsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unable to load appointments: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _retryAppointments,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final appointments = snapshot.data ?? const <Appointment>[];
        if (appointments.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No appointments scheduled yet.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: appointments.length,
          itemBuilder: (context, index) {
            final appointment = appointments[index];
            return AppointmentCard(
              appointment: appointment,
              isUpdating: _updatingAppointmentIds.contains(appointment.id),
              onApprove: () =>
                  _updateAppointmentStatus(appointment, 'confirmed'),
              onCancel: () =>
                  _updateAppointmentStatus(appointment, 'cancelled'),
            );
          },
        );
      },
    );
  }
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    required this.appointment,
    required this.isUpdating,
    required this.onApprove,
    required this.onCancel,
    super.key,
  });

  final Appointment appointment;
  final bool isUpdating;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = appointment.status.toLowerCase();
    final statusColor = switch (status) {
      'confirmed' => Colors.green,
      'pending' => Colors.orange,
      'cancelled' => Colors.red,
      _ => Colors.blueGrey,
    };
    final statusLabel = status.isEmpty
        ? 'Unknown'
        : '${status[0].toUpperCase()}${status.substring(1)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appointment.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Theme.of(context).colorScheme.surface,
                      statusColor,
                      0.14,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Text(DateFormat.yMMMd().add_jm().format(appointment.dateTime)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reason: ${appointment.reason}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isUpdating || status == 'pending' || status == 'confirmed') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isUpdating)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    if (status == 'pending')
                      IconButton(
                        tooltip: 'Approve appointment',
                        onPressed: onApprove,
                        color: Colors.green,
                        icon: const Icon(Icons.check_circle_outline),
                      ),
                    IconButton(
                      tooltip: 'Cancel appointment',
                      onPressed: onCancel,
                      color: Colors.red,
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
