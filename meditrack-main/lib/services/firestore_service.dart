import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../models/medical_document.dart';
import '../models/medical_record.dart';
import '../models/patient_profile.dart';

class FirestoreService {
  static final Map<String, AppUser> demoUsers = {};
  static final Map<String, String> demoPasswords = {};
  static final Map<String, PatientProfile> demoProfiles = {};
  static final Map<String, MedicalRecord> demoRecords = {};
  static final Map<String, MedicalDocument> demoDocuments = {};
  static final Map<String, Set<String>> demoDoctorAccess = {};
  static bool _demoDataLoaded = false;

  static Future<void> initializeDemoData() async {
    if (_demoDataLoaded) return;
    await _loadDemoData();
    _demoDataLoaded = true;
  }

  static Future<void> _loadDemoData() async {
    final preferences = await SharedPreferences.getInstance();
    final usersJson = preferences.getString('demo_users');
    if (usersJson != null) {
      final users = jsonDecode(usersJson) as Map<String, dynamic>;
      for (final entry in users.entries) {
        final data = Map<String, dynamic>.from(entry.value as Map);
        final createdAt = DateTime.parse(data['createdAt'] as String);
        demoUsers[entry.key] = AppUser(
          uid: data['uid'] as String,
          name: data['name'] as String,
          email: data['email'] as String,
          role: data['role'] as String,
          isActive: data['isActive'] as bool,
          createdAt: createdAt,
        );
      }
    }

    final passwordsJson = preferences.getString('demo_passwords');
    if (passwordsJson != null) {
      demoPasswords.addAll(
        Map<String, String>.from(jsonDecode(passwordsJson) as Map),
      );
    }

    final profilesJson = preferences.getString('demo_profiles');
    if (profilesJson != null) {
      final profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
      for (final entry in profiles.entries) {
        demoProfiles[entry.key] = PatientProfile.fromMap(
          entry.key,
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }

    final recordsJson = preferences.getString('demo_records');
    if (recordsJson != null) {
      final records = jsonDecode(recordsJson) as Map<String, dynamic>;
      for (final entry in records.entries) {
        demoRecords[entry.key] = MedicalRecord.fromMap(
          entry.key,
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }

    final documentsJson = preferences.getString('demo_documents');
    if (documentsJson != null) {
      final documents = jsonDecode(documentsJson) as Map<String, dynamic>;
      for (final entry in documents.entries) {
        demoDocuments[entry.key] = MedicalDocument.fromMap(
          entry.key,
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }

    final accessJson = preferences.getString('demo_doctor_access');
    if (accessJson != null) {
      final access = jsonDecode(accessJson) as Map<String, dynamic>;
      for (final entry in access.entries) {
        demoDoctorAccess[entry.key] = Set<String>.from(entry.value as List);
      }
    }
  }

  static Future<void> persistDemoData() async {
    final preferences = await SharedPreferences.getInstance();
    final users = demoUsers.map(
      (key, user) => MapEntry(key, {
        'uid': user.uid,
        'name': user.name,
        'email': user.email,
        'role': user.role,
        'isActive': user.isActive,
        'createdAt': user.createdAt.toIso8601String(),
      }),
    );
    final profiles = demoProfiles.map(
      (key, profile) => MapEntry(key, profile.toMap()),
    );
    final records = demoRecords.map(
      (key, record) => MapEntry(key, record.toJson()),
    );
    final documents = demoDocuments.map(
      (key, document) => MapEntry(key, document.toJson()),
    );
    final doctorAccess = demoDoctorAccess.map(
      (key, doctorIds) => MapEntry(key, doctorIds.toList()),
    );
    await preferences.setString('demo_users', jsonEncode(users));
    await preferences.setString('demo_passwords', jsonEncode(demoPasswords));
    await preferences.setString('demo_profiles', jsonEncode(profiles));
    await preferences.setString('demo_records', jsonEncode(records));
    await preferences.setString('demo_documents', jsonEncode(documents));
    await preferences.setString(
      'demo_doctor_access',
      jsonEncode(doctorAccess),
    );
  }

  static Future<void> reloadDemoData() async {
    _demoDataLoaded = false;
    demoUsers.clear();
    demoPasswords.clear();
    demoProfiles.clear();
    demoRecords.clear();
    demoDocuments.clear();
    demoDoctorAccess.clear();
    await initializeDemoData();
  }

  static Future<String?> loadDemoSessionUid() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('demo_session_uid');
  }

  static Future<void> saveDemoSessionUid(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('demo_session_uid', uid);
  }

  static Future<void> clearDemoSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('demo_session_uid');
  }

  FirebaseFirestore? _db;

  FirestoreService() {
    if (Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig) {
      _db = FirebaseFirestore.instance;
    }
  }

  bool get _isAvailable =>
      Firebase.apps.isNotEmpty && !DefaultFirebaseOptions.isDemoConfig;

  bool get _isDemoMode => !_isAvailable;

  FirebaseFirestore get db => _db ?? _throwNoApp();

  FirebaseFirestore _throwNoApp() {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'no-app',
      message: 'No Firebase app has been initialized.',
    );
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _patientsCollection() =>
      db.collection('patients');

  CollectionReference<Map<String, dynamic>> _recordsCollection() =>
      db.collection('records');

  CollectionReference<Map<String, dynamic>> _documentsCollection() =>
      db.collection('documents');

  Future<void> saveUserProfile(AppUser user) async {
    if (_isDemoMode) {
      demoUsers[user.uid] = user;
      await persistDemoData();
      return;
    }
    await _userDoc(user.uid).set(user.toMap(), SetOptions(merge: true));
  }

  Future<AppUser?> fetchUser(String uid) async {
    if (_isDemoMode) return demoUsers[uid];
    final snap = await _userDoc(uid).get();
    if (!snap.exists) return null;
    return AppUser.fromMap(uid, snap.data() ?? {});
  }

  Future<void> savePatientProfile(String uid, PatientProfile profile) async {
    if (_isDemoMode) {
      demoProfiles[uid] = profile;
      await persistDemoData();
      return;
    }
    await _patientsCollection()
        .doc(uid)
        .set(profile.toMap(), SetOptions(merge: true));
  }

  Future<PatientProfile?> fetchPatientProfile(String uid) async {
    if (_isDemoMode) return demoProfiles[uid];
    final snap = await _patientsCollection().doc(uid).get();
    if (!snap.exists) return null;
    return PatientProfile.fromMap(uid, snap.data() ?? {});
  }

  Future<void> updateUserActiveStatus(String uid, bool isActive) async {
    if (_isDemoMode) {
      final user = demoUsers[uid];
      if (user != null) {
        demoUsers[uid] = AppUser(
          uid: user.uid,
          name: user.name,
          email: user.email,
          role: user.role,
          isActive: isActive,
          createdAt: user.createdAt,
        );
      }
      await persistDemoData();
      return;
    }
    await _userDoc(uid).update({'isActive': isActive});
  }

  Future<void> deleteUser(String uid) async {
    if (_isDemoMode) {
      demoUsers.remove(uid);
      demoProfiles.remove(uid);
      demoRecords.removeWhere((_, record) => record.patientId == uid);
      demoDocuments.removeWhere((_, doc) => doc.patientId == uid);
      await persistDemoData();
      return;
    }
    await _userDoc(uid).delete();
    await _patientsCollection().doc(uid).delete();
  }

  Future<List<AppUser>> fetchUsersByRole(String role) async {
    if (_isDemoMode) {
      return demoUsers.values.where((user) => user.role == role).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final snap = await db
        .collection('users')
        .where('role', isEqualTo: role)
        .orderBy('createdAt', descending: true)
        .get();

    return snap.docs.map((doc) => AppUser.fromMap(doc.id, doc.data())).toList();
  }

  Future<List<AppUser>> fetchAllUsers() async {
    if (_isDemoMode) {
      return demoUsers.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final snap = await db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((doc) => AppUser.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> addRecord(MedicalRecord record) async {
    if (_isDemoMode) {
      await initializeDemoData();
      demoRecords[record.recordId] = record;
      await persistDemoData();
      return;
    }
    final ref = _recordsCollection().doc(record.recordId);
    await ref.set(record.toMap());
  }

  Future<void> updateRecord(MedicalRecord record) async {
    if (_isDemoMode) {
      await initializeDemoData();
      demoRecords[record.recordId] = record;
      await persistDemoData();
      return;
    }
    await _recordsCollection().doc(record.recordId).update(record.toMap());
  }

  Future<void> deleteRecord(String recordId) async {
    if (_isDemoMode) {
      await initializeDemoData();
      demoRecords.remove(recordId);
      demoDocuments.removeWhere((_, document) => document.recordId == recordId);
      await persistDemoData();
      return;
    }
    await _recordsCollection().doc(recordId).delete();
    final docs = await _documentsCollection()
        .where('recordId', isEqualTo: recordId)
        .get();
    for (final doc in docs.docs) {
      await doc.reference.delete();
    }
  }

  Future<List<MedicalRecord>> fetchRecordsForPatient(String patientId) async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoRecords.values
          .where((record) => record.patientId == patientId)
          .toList()
        ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    }
    final snap = await _recordsCollection()
        .where('patientId', isEqualTo: patientId)
        .orderBy('visitDate', descending: true)
        .get();

    return snap.docs
        .map((doc) => MedicalRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<MedicalRecord>> fetchAllRecords() async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoRecords.values.toList()
        ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    }
    final snap = await _recordsCollection()
        .orderBy('visitDate', descending: true)
        .get();
    return snap.docs
        .map((doc) => MedicalRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<AppUser>> searchPatientsByNameOrEmail(String query) async {
    if (_isDemoMode) {
      final q = query.trim().toLowerCase();
      final patients = demoUsers.values
          .where((user) => user.role == 'Patient')
          .where(
            (user) =>
                q.isEmpty ||
                user.name.toLowerCase().contains(q) ||
                user.email.toLowerCase().contains(q),
          )
          .toList();
      patients.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return patients;
    }
    final q = query.trim();
    if (q.isEmpty) {
      return fetchUsersByRole('Patient');
    }

    final snap = await db
        .collection('users')
        .where('role', isEqualTo: 'Patient')
        .get();

    final matches = snap.docs.where((doc) {
      final data = doc.data();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final email = (data['email'] ?? '').toString().toLowerCase();
      final needle = q.toLowerCase();
      return name.contains(needle) || email.contains(needle);
    }).toList();

    return matches.map((doc) => AppUser.fromMap(doc.id, doc.data())).toList();
  }

  Future<List<MedicalDocument>> fetchDocumentsForRecord(
    String recordId, {
    String? patientId,
  }) async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoDocuments.values
          .where((document) => document.recordId == recordId)
          .where((document) => patientId == null || document.patientId == patientId)
          .toList();
    }
    var query = _documentsCollection()
        .where('recordId', isEqualTo: recordId);
    if (patientId != null) {
      query = query.where('patientId', isEqualTo: patientId);
    }
    final snap = await query.limit(100).get();
    return snap.docs
        .map((doc) => MedicalDocument.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<MedicalDocument>> fetchDocumentsForPatient(
    String patientId,
  ) async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoDocuments.values
          .where((document) => document.patientId == patientId)
          .toList()
        ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    }
    final snapshot = await _documentsCollection()
        .where('patientId', isEqualTo: patientId)
        .limit(500)
        .get();
    return snapshot.docs
        .map((doc) => MedicalDocument.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
  }

  Future<MedicalDocument?> fetchDocument(String documentId) async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoDocuments[documentId];
    }
    final snapshot = await _documentsCollection().doc(documentId).get();
    if (!snapshot.exists) return null;
    return MedicalDocument.fromMap(snapshot.id, snapshot.data() ?? {});
  }

  Future<void> saveDocument(MedicalDocument document) async {
    if (_isDemoMode) {
      await initializeDemoData();
      demoDocuments[document.documentId] = document;
      await persistDemoData();
      return;
    }
    await _documentsCollection().doc(document.documentId).set(document.toMap());
  }

  Future<void> updateDocument(MedicalDocument document) async {
    if (_isDemoMode) {
      await initializeDemoData();
      if (!demoDocuments.containsKey(document.documentId)) {
        throw StateError('This report no longer exists.');
      }
      demoDocuments[document.documentId] = document;
      await persistDemoData();
      return;
    }
    final reference = _documentsCollection().doc(document.documentId);
    await reference.update({
      'reportTitle': document.reportTitle,
      'reportCategory': document.reportCategory,
      'doctorName': document.doctorName,
      'hospitalName': document.hospitalName,
      'reportDate': Timestamp.fromDate(document.reportDate),
      'description': document.description,
    });
  }

  Future<void> deleteDocument(String documentId) async {
    if (_isDemoMode) {
      await initializeDemoData();
      demoDocuments.remove(documentId);
      await persistDemoData();
      return;
    }
    await _documentsCollection().doc(documentId).delete();
  }

  Future<void> grantDoctorAccess({
    required String patientId,
    required String doctorId,
  }) async {
    if (patientId == doctorId || doctorId.trim().isEmpty) {
      throw ArgumentError('Enter a valid doctor account ID.');
    }
    if (_isDemoMode) {
      await initializeDemoData();
      if (!demoUsers.values.any(
        (user) => user.uid == doctorId && user.role == 'Doctor',
      )) {
        throw StateError('No doctor account was found for that ID.');
      }
      demoDoctorAccess.putIfAbsent(patientId, () => <String>{}).add(doctorId);
      await persistDemoData();
      return;
    }
    await _userDoc(patientId).update({
      'authorizedDoctors': FieldValue.arrayUnion([doctorId]),
    });
  }

  Future<void> revokeDoctorAccess({
    required String patientId,
    required String doctorId,
  }) async {
    if (_isDemoMode) {
      await initializeDemoData();
      demoDoctorAccess[patientId]?.remove(doctorId);
      if (demoDoctorAccess[patientId]?.isEmpty ?? false) {
        demoDoctorAccess.remove(patientId);
      }
      await persistDemoData();
      return;
    }
    await _userDoc(patientId).update({
      'authorizedDoctors': FieldValue.arrayRemove([doctorId]),
    });
  }

  Future<List<String>> fetchAuthorizedDoctorIds(String patientId) async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoDoctorAccess[patientId]?.toList() ?? const [];
    }
    final patient = await _userDoc(patientId).get();
    return List<String>.from(patient.data()?['authorizedDoctors'] ?? const []);
  }

  Future<List<AppUser>> fetchPatientsSharedWithDoctor(String doctorId) async {
    if (_isDemoMode) {
      await initializeDemoData();
      return demoUsers.values
          .where((user) => user.role == 'Patient')
          .where(
            (user) => demoDoctorAccess[user.uid]?.contains(doctorId) ?? false,
          )
          .toList();
    }
    final snapshot = await db
        .collection('users')
        .where('role', isEqualTo: 'Patient')
        .where('authorizedDoctors', arrayContains: doctorId)
        .limit(200)
        .get();
    return snapshot.docs
        .map((doc) => AppUser.fromMap(doc.id, doc.data()))
        .toList();
  }
}
