import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../models/medicine.dart';
import '../models/scheduled_dose.dart';

typedef MedicineNotificationAction = Future<void> Function(
  String patientId,
  String medicineId,
  String doseId,
  String action,
);

class MedicineNotificationService {
  factory MedicineNotificationService() => _instance;

  MedicineNotificationService._();

  static final _instance = MedicineNotificationService._();
  static const _channelId = 'medicine_dose_reminders';
  static const _categoryId = 'medicine_dose_actions';
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  MedicineNotificationAction? _onAction;

  Future<void> initialize({
    required MedicineNotificationAction onAction,
  }) async {
    _onAction = onAction;
    _initialization ??= _initializePlugin();
    await _initialization;
  }

  Future<bool> requestPermission() async {
    await _initialization;
    if (kIsWeb) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (mac != null) {
      return await mac.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<void> sync({
    required String patientId,
    required List<Medicine> medicines,
    required List<ScheduledDose> doses,
  }) async {
    await _initialization;
    final medicineById = {
      for (final medicine in medicines) medicine.id: medicine,
    };
    final now = DateTime.now();
    final eligible =
        doses
            .where(
              (dose) =>
                  dose.patientId == patientId &&
                  dose.status == 'pending' &&
                  medicineById.containsKey(dose.medicineId) &&
                  !dose.scheduledAt.isBefore(
                    now.subtract(const Duration(minutes: 30)),
                  ),
            )
            .toList()
          ..sort((a, b) => _alertTime(a).compareTo(_alertTime(b)));
    final desired = eligible.take(48).toList();
    final desiredIds = desired.map((dose) => dose.id).toSet();
    final preferences = await SharedPreferences.getInstance();
    final key = _scheduledKey(patientId);
    final remembered = preferences.getStringList(key) ?? <String>[];
    final retained = remembered.where(desiredIds.contains).toSet();

    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      final payload = _decodePayload(notification.payload);
      if (payload?['patientId'] == patientId &&
          !desiredIds.contains(payload?['doseId'])) {
        await _plugin.cancel(id: notification.id);
      }
    }

    for (final dose in desired) {
      final medicine = medicineById[dose.medicineId]!;
      final id = notificationId(dose.id);
      if (retained.contains(dose.id)) continue;
      await _schedule(medicine, dose, _alertTime(dose));
      retained.add(dose.id);
      await preferences.setStringList(key, retained.toList());
      if (id < 0) {
        throw StateError('Notification id must be non-negative.');
      }
    }
    await preferences.setStringList(key, retained.toList());
  }

  Future<void> scheduleSnoozedDose({
    required String patientId,
    required Medicine medicine,
    required ScheduledDose dose,
    required DateTime snoozedUntil,
  }) async {
    await _initialization;
    await _schedule(medicine, dose, snoozedUntil);
    final preferences = await SharedPreferences.getInstance();
    final key = _scheduledKey(patientId);
    final ids = preferences.getStringList(key) ?? <String>[];
    if (!ids.contains(dose.id)) ids.add(dose.id);
    await preferences.setStringList(key, ids);
  }

  Future<void> cancelDose(String patientId, String doseId) async {
    await _initialization;
    await _plugin.cancel(id: notificationId(doseId));
    final preferences = await SharedPreferences.getInstance();
    final key = _scheduledKey(patientId);
    final ids = preferences.getStringList(key) ?? <String>[];
    ids.remove(doseId);
    await preferences.setStringList(key, ids);
  }

  Future<void> cancelMedicine({
    required String patientId,
    required String medicineId,
    required Iterable<String> doseIds,
  }) async {
    await _initialization;
    final cancelledIds = doseIds.toSet();
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      final payload = _decodePayload(notification.payload);
      if (payload?['patientId'] == patientId &&
          payload?['medicineId'] == medicineId) {
        await _plugin.cancel(id: notification.id);
        cancelledIds.add(payload!['doseId']!);
      }
    }
    final preferences = await SharedPreferences.getInstance();
    final key = _scheduledKey(patientId);
    final ids = preferences.getStringList(key) ?? <String>[];
    ids.removeWhere(cancelledIds.contains);
    await preferences.setStringList(key, ids);
  }

  Future<void> cancelAll() async {
    await _initialization;
    await _plugin.cancelAll();
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith('medicine_notifications_scheduled_'),
    )) {
      await preferences.remove(key);
    }
  }

  Future<void> _initializePlugin() async {
    timezone_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localTimezone.identifier));

    final actions = <DarwinNotificationAction>[
      DarwinNotificationAction.plain(
        'taken',
        'Taken',
        options: {DarwinNotificationActionOption.foreground},
      ),
      DarwinNotificationAction.plain(
        'snooze',
        'Snooze 10 min',
        options: {DarwinNotificationActionOption.foreground},
      ),
      DarwinNotificationAction.plain(
        'skipped',
        'Skip',
        options: {DarwinNotificationActionOption.foreground},
      ),
    ];
    final category = DarwinNotificationCategory(_categoryId, actions: actions);
    await _plugin.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [category],
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [category],
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Open reminder'),
        windows: WindowsInitializationSettings(
          appName: 'Meditrack',
          appUserModelId: 'com.example.meditrack',
          guid: '{EF8D4C5A-0C08-4D0A-8A18-7A504C628E71}',
        ),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true && response != null) {
      unawaited(_handleResponse(response));
    }
  }

  Future<void> _handleResponse(NotificationResponse response) async {
    final action = response.actionId;
    if (action == null ||
        !const {'taken', 'snooze', 'skipped'}.contains(action)) {
      return;
    }
    final payload = _decodePayload(response.payload);
    if (payload == null) return;
    await _onAction?.call(
      payload['patientId']!,
      payload['medicineId']!,
      payload['doseId']!,
      action,
    );
  }

  Future<void> _schedule(
    Medicine medicine,
    ScheduledDose dose,
    DateTime alertTime,
  ) async {
    final now = DateTime.now();
    final target = alertTime.isBefore(now)
        ? now.add(const Duration(seconds: 1))
        : alertTime;
    await _plugin.zonedSchedule(
      id: notificationId(dose.id),
      title: 'Medicine reminder: ${medicine.name}',
      body: '${medicine.dosage} • ${medicine.instructions}',
      scheduledDate: timezone.TZDateTime.from(target, timezone.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Medicine reminders',
          channelDescription: 'Reminders for scheduled medicine doses',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(
              'taken',
              'Taken',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'snooze',
              'Snooze 10 min',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'skipped',
              'Skip',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _categoryId),
        macOS: DarwinNotificationDetails(categoryIdentifier: _categoryId),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({
        'patientId': dose.patientId,
        'medicineId': dose.medicineId,
        'doseId': dose.id,
      }),
    );
  }

  static DateTime _alertTime(ScheduledDose dose) =>
      dose.snoozedUntil ?? dose.scheduledAt;

  static Map<String, String>? _decodePayload(String? payload) {
    if (payload == null) return null;
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final patientId = decoded['patientId'] as String?;
    final medicineId = decoded['medicineId'] as String?;
    final doseId = decoded['doseId'] as String?;
    if (patientId == null || medicineId == null || doseId == null) return null;
    return {'patientId': patientId, 'medicineId': medicineId, 'doseId': doseId};
  }

  static String _scheduledKey(String patientId) =>
      'medicine_notifications_scheduled_$patientId';

  static int notificationId(String doseId) {
    var hash = 0x811c9dc5;
    for (final unit in doseId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
