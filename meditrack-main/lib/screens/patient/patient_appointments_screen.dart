import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../firebase_options.dart';
import '../../models/appointment.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  State<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState extends State<PatientAppointmentsScreen> {
  late final Stream<List<Appointment>> _appointmentsStream;

  static const _mockDoctorNames = {
    'doc1': 'Dr. Sarah Ahmed',
    'doc2': 'Dr. James Wilson',
    'doc3': 'Dr. Ayesha Khan',
  };

  @override
  void initState() {
    super.initState();
    final firebaseUserId =
        Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    final patientId =
        firebaseUserId ?? context.read<AppAuthProvider>().appUser!.uid;
    _appointmentsStream = FirestoreService().streamPatientAppointments(
      patientId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Appointments')),
      body: StreamBuilder<List<Appointment>>(
        stream: _appointmentsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load appointments: ${snapshot.error}',
                  textAlign: TextAlign.center,
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
                  'You have no appointment requests yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: appointments.length,
            itemBuilder: (context, index) =>
                _appointmentCard(appointments[index]),
          );
        },
      ),
    );
  }

  Widget _appointmentCard(Appointment appointment) {
    final status = appointment.status.toLowerCase();
    final statusColor = switch (status) {
      'pending' => Colors.orange,
      'confirmed' => Colors.green,
      'cancelled' => Colors.red,
      _ => Colors.blueGrey,
    };
    final doctorName = appointment.doctorName?.trim().isNotEmpty == true
        ? appointment.doctorName!.trim()
        : _mockDoctorNames[appointment.doctorId] ??
              'Doctor ${appointment.doctorId}';
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
                    doctorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
          ],
        ),
      ),
    );
  }
}
