import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/medicine.dart';
import '../../models/scheduled_dose.dart';
import '../../providers/auth_provider.dart';
import '../../services/medicine_notification_service.dart';
import '../../services/medicine_reminder_service.dart';
import 'medicine_form_screen.dart';

class MedicineReminderScreen extends StatefulWidget {
  const MedicineReminderScreen({super.key});

  @override
  State<MedicineReminderScreen> createState() => _MedicineReminderScreenState();
}

class _MedicineReminderScreenState extends State<MedicineReminderScreen> {
  final _service = MedicineReminderService();
  final _notifications = MedicineNotificationService();
  List<Medicine> _medicines = const [];
  List<ScheduledDose> _doses = const [];
  String _statusFilter = 'active';
  String? _error;
  String? _notificationMessage;
  bool _loading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final title = _tabIndex == 0 ? 'Medicine reminders' : 'Medicine history';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_tabIndex == 0)
            IconButton(
              tooltip: 'Add medicine',
              onPressed: _loading ? null : _openAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorState()
          : _tabIndex == 0
          ? _dashboard()
          : _history(),
      floatingActionButton: _tabIndex == 0 && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: _openAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add medicine'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: 'Medicines',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }

  Widget _dashboard() {
    final now = DateTime.now();
    final active = _medicines.where(
      (medicine) => medicine.statusOn(now) == 'active',
    );
    final upcoming =
        _doses
            .where(
              (dose) =>
                  dose.status == 'pending' &&
                  !dose.scheduledAt.isBefore(
                    now.subtract(MedicineReminderService.missedWindow),
                  ),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final takenToday = _doses
        .where(
          (dose) =>
              dose.status == 'taken' && _isSameDate(dose.scheduledAt, now),
        )
        .length;
    final missedToday = _doses
        .where(
          (dose) =>
              dose.status == 'missed' && _isSameDate(dose.scheduledAt, now),
        )
        .length;
    final visibleMedicines = _medicines
        .where((medicine) => medicine.statusOn(now) == _statusFilter)
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _welcomeCard(active.length),
          if (_notificationMessage != null) ...[
            const SizedBox(height: 12),
            _notificationNotice(),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  label: 'Upcoming',
                  value: upcoming.length.toString(),
                  icon: Icons.notifications_active_outlined,
                  color: const Color(0xff087e8b),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard(
                  label: 'Taken today',
                  value: takenToday.toString(),
                  icon: Icons.check_circle_outline,
                  color: const Color(0xff29805b),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard(
                  label: 'Missed today',
                  value: missedToday.toString(),
                  icon: Icons.error_outline,
                  color: const Color(0xffc15a43),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle('Next doses'),
          const SizedBox(height: 10),
          if (upcoming.isEmpty)
            _emptyCard(
              icon: Icons.notifications_none,
              title: 'No doses scheduled',
              message: 'Your upcoming doses will appear here.',
            )
          else
            ...upcoming.take(5).map(_doseCard),
          const SizedBox(height: 24),
          _sectionTitle('Your medicines'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final status in const [
                ('active', 'Active'),
                ('completed', 'Completed'),
                ('discontinued', 'Discontinued'),
              ])
                ChoiceChip(
                  label: Text(status.$2),
                  selected: _statusFilter == status.$1,
                  onSelected: (_) => setState(() => _statusFilter = status.$1),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibleMedicines.isEmpty)
            _emptyCard(
              icon: Icons.medication_outlined,
              title: _statusFilter == 'active'
                  ? 'No active medicines'
                  : 'Nothing to show',
              message: _statusFilter == 'active'
                  ? 'Add a medicine to create a reminder schedule.'
                  : 'Medicines with this status will appear here.',
            )
          else
            ...visibleMedicines.map(_medicineCard),
        ],
      ),
    );
  }

  Widget _welcomeCard(int activeCount) {
    final userName = context.read<AppAuthProvider>().appUser?.name ?? 'Patient';
    return Card(
      color: const Color(0xffeaf6f8),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 25,
              backgroundColor: Color(0xffc6e8ed),
              child: Icon(Icons.health_and_safety, color: Color(0xff087e8b)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $userName',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$activeCount active ${activeCount == 1 ? 'medicine' : 'medicines'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  Widget _sectionTitle(String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700),
  );

  Widget _doseCard(ScheduledDose dose) {
    final medicine = _medicineById(dose.medicineId);
    if (medicine == null) return const SizedBox.shrink();
    final time = dose.snoozedUntil ?? dose.scheduledAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm, color: Color(0xff087e8b)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medicine.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${medicine.dosage} • ${DateFormat.MMMd().add_jm().format(time)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _actOnDose(dose, 'taken'),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Taken'),
                ),
                OutlinedButton(
                  onPressed: () => _actOnDose(dose, 'snooze'),
                  child: const Text('Snooze 10 min'),
                ),
                TextButton(
                  onPressed: () => _actOnDose(dose, 'skipped'),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _medicineCard(Medicine medicine) {
    final nextDose =
        _doses
            .where(
              (dose) =>
                  dose.medicineId == medicine.id &&
                  dose.status == 'pending' &&
                  !dose.scheduledAt.isBefore(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final status = medicine.statusOn(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xffeaf6f8),
                  child: Icon(Icons.medication, color: Color(0xff087e8b)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medicine.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text('${medicine.dosage} • ${medicine.frequency}'),
                    ],
                  ),
                ),
                _statusBadge(status),
                PopupMenuButton<String>(
                  tooltip: 'Medicine actions',
                  onSelected: (action) {
                    if (action == 'edit') _openEdit(medicine);
                    if (action == 'discontinue') _discontinue(medicine);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    if (status == 'active')
                      const PopupMenuItem(
                        value: 'discontinue',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.pause_circle_outline),
                          title: Text('Discontinue'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _iconText(Icons.schedule, medicine.reminderTimes.join(', ')),
                _iconText(
                  Icons.calendar_month_outlined,
                  '${DateFormat.yMMMd().format(medicine.startDate)} - ${DateFormat.yMMMd().format(medicine.endDate)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _iconText(Icons.restaurant_outlined, medicine.instructions),
            const SizedBox(height: 8),
            Text(
              nextDose.isEmpty
                  ? 'Next dose: none scheduled'
                  : 'Next dose: ${DateFormat.MMMd().add_jm().format(nextDose.first.scheduledAt)}',
              style: const TextStyle(
                color: Color(0xff087e8b),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (medicine.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                medicine.notes,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _history() {
    final now = DateTime.now();
    final today = _doses
        .where((dose) => _isSameDate(dose.scheduledAt, now))
        .toList();
    final week = _doses.where((dose) {
      final elapsed = now.difference(dose.scheduledAt);
      return !elapsed.isNegative && elapsed < const Duration(days: 7);
    }).toList();
    final history =
        _doses
            .where(
              (dose) =>
                  !dose.scheduledAt.isAfter(now) && dose.status != 'cancelled',
            )
            .toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: _adherenceCard('Today', today)),
              const SizedBox(width: 12),
              Expanded(child: _adherenceCard('Last 7 days', week)),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle('Dose history'),
          const SizedBox(height: 10),
          if (history.isEmpty)
            _emptyCard(
              icon: Icons.history,
              title: 'No dose history yet',
              message: 'Recorded and missed doses will appear here.',
            )
          else
            ...history.map(_historyDoseCard),
        ],
      ),
    );
  }

  Widget _adherenceCard(String title, List<ScheduledDose> doses) {
    final resolved = doses.where(
      (dose) => const {'taken', 'skipped', 'missed'}.contains(dose.status),
    );
    final taken = resolved.where((dose) => dose.status == 'taken').length;
    final percent = resolved.isEmpty
        ? 0
        : (taken * 100 / resolved.length).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '$percent%',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xff087e8b),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text('$taken of ${resolved.length} recorded doses taken'),
          ],
        ),
      ),
    );
  }

  Widget _historyDoseCard(ScheduledDose dose) {
    final medicine = _medicineById(dose.medicineId);
    if (medicine == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(dose.status).withValues(alpha: .12),
          child: Icon(
            _statusIcon(dose.status),
            color: _statusColor(dose.status),
          ),
        ),
        title: Text(medicine.name),
        subtitle: Text(
          '${medicine.dosage} • Scheduled ${DateFormat.MMMd().add_jm().format(dose.scheduledAt)}'
          '${dose.takenAt == null ? '' : '\nTaken ${DateFormat.MMMd().add_jm().format(dose.takenAt!)}'}',
        ),
        isThreeLine: dose.takenAt != null,
        trailing: _statusBadge(dose.status),
      ),
    );
  }

  Widget _statusBadge(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _statusColor(status).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _capitalize(status),
      style: TextStyle(
        color: _statusColor(status),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _iconText(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: Colors.blueGrey),
      const SizedBox(width: 5),
      Flexible(child: Text(text)),
    ],
  );

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String message,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, size: 34, color: Colors.blueGrey),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _notificationNotice() => Card(
    color: const Color(0xfffff5db),
    child: ListTile(
      leading: const Icon(Icons.notifications_off_outlined),
      title: Text(_notificationMessage!),
      trailing: TextButton(
        onPressed: _requestNotificationPermission,
        child: const Text('Enable'),
      ),
    ),
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Future<void> _load() async {
    final patientId = context.read<AppAuthProvider>().appUser?.uid;
    if (patientId == null) {
      setState(() {
        _error = 'Sign in as a patient to manage medicine reminders.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _notifications.initialize(onAction: _handleNotificationAction);
      final granted = await _notifications.requestPermission();
      final medicines = await _service.fetchMedicines(patientId);
      final doses = await _service.fetchDoses(patientId);
      if (granted) {
        await _notifications.sync(
          patientId: patientId,
          medicines: medicines,
          doses: doses,
        );
      }
      if (!mounted) return;
      setState(() {
        _medicines = medicines;
        _doses = doses;
        _notificationMessage = granted ? null : 'Notifications are disabled. Reminders will not appear when the app is closed.';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load medicine reminders: $error';
        _loading = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final granted = await _notifications.requestPermission();
      if (!mounted) return;
      setState(() {
        _notificationMessage = granted ? null : 'Notification permission was not granted. You can enable it in device settings.';
      });
      if (granted) await _load();
    } catch (error) {
      if (mounted) {
        _showMessage('Could not request notification permission: $error');
      }
    }
  }

  Future<void> _openAdd() async {
    final patientId = context.read<AppAuthProvider>().appUser!.uid;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicineFormScreen(patientId: patientId),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _openEdit(Medicine medicine) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicineFormScreen(
          patientId: medicine.patientId,
          medicine: medicine,
        ),
      ),
    );
    if (saved == true) {
      await _notifications.cancelMedicine(
        patientId: medicine.patientId,
        medicineId: medicine.id,
        doseIds: _doses
            .where((dose) => dose.medicineId == medicine.id)
            .map((dose) => dose.id),
      );
      await _load();
    }
  }

  Future<void> _discontinue(Medicine medicine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discontinue medicine?'),
        content: Text(
          'Future reminders for ${medicine.name} will be cancelled. This does not change any prescription.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep active'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discontinue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.discontinueMedicine(medicine.patientId, medicine.id);
      await _load();
    } catch (error) {
      _showMessage('Unable to discontinue medicine: $error');
    }
  }

  Future<void> _actOnDose(ScheduledDose dose, String action) async {
    final patientId = context.read<AppAuthProvider>().appUser?.uid;
    if (patientId == null || patientId != dose.patientId) {
      _showMessage('This dose is not available for the signed-in patient.');
      return;
    }
    try {
      await _service.recordDoseAction(
        patientId: patientId,
        medicineId: dose.medicineId,
        doseId: dose.id,
        action: action,
      );
      if (action == 'snooze') {
        final updatedDose = dose;
        final medicine = _medicineById(dose.medicineId);
        if (medicine != null) {
          await _notifications.scheduleSnoozedDose(
            patientId: patientId,
            medicine: medicine,
            dose: updatedDose,
            snoozedUntil: DateTime.now().add(const Duration(minutes: 10)),
          );
        }
      } else {
        await _notifications.cancelDose(patientId, dose.id);
      }
      await _load();
    } catch (error) {
      _showMessage('Unable to record dose action: $error');
    }
  }

  Future<void> _handleNotificationAction(
    String patientId,
    String medicineId,
    String doseId,
    String action,
  ) async {
    if (!mounted || context.read<AppAuthProvider>().appUser?.uid != patientId) {
      return;
    }
    try {
      await _service.recordDoseAction(
        patientId: patientId,
        medicineId: medicineId,
        doseId: doseId,
        action: action,
      );
      if (action == 'snooze') {
        final medicines = await _service.fetchMedicines(patientId);
        final doses = await _service.fetchDoses(patientId);
        final medicine = medicines
            .where((item) => item.id == medicineId)
            .firstOrNull;
        final dose = doses.where((item) => item.id == doseId).firstOrNull;
        if (dose == null || medicine == null) {
          throw StateError('Snoozed dose could not be reloaded.');
        }
        await _notifications.scheduleSnoozedDose(
          patientId: patientId,
          medicine: medicine,
          dose: dose,
          snoozedUntil: DateTime.now().add(const Duration(minutes: 10)),
        );
      } else {
        await _notifications.cancelDose(patientId, doseId);
      }
      await _load();
    } catch (error) {
      if (mounted) _showMessage('Unable to record dose action: $error');
    }
  }

  Future<void> _signOut() async {
    await _notifications.cancelAll();
    if (mounted) await context.read<AppAuthProvider>().signOut();
  }

  Medicine? _medicineById(String id) {
    for (final medicine in _medicines) {
      if (medicine.id == id) return medicine;
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static Color _statusColor(String status) => switch (status) {
    'taken' || 'active' => const Color(0xff29805b),
    'skipped' || 'completed' => const Color(0xff687982),
    'missed' || 'discontinued' => const Color(0xffc15a43),
    _ => const Color(0xff087e8b),
  };

  static IconData _statusIcon(String status) => switch (status) {
    'taken' => Icons.check_circle_outline,
    'skipped' => Icons.do_not_disturb_on_outlined,
    'missed' => Icons.error_outline,
    _ => Icons.schedule,
  };

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static bool _isSameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
