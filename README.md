# MedTrack – Medical Records Manager

A Flutter + Firebase mini-project for patient, doctor, and admin workflows.

## Tech stack
- Flutter + Dart
- Material 3
- Provider for state management
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Device-local notifications with `flutter_local_notifications`
- file_picker, image_picker, url_launcher, intl, pdfrx, file_saver

## Project structure

```text
lib/
  main.dart
  firebase_options.dart
  models/
    app_user.dart
    patient_profile.dart
    medical_record.dart
    medical_document.dart
    medicine.dart
    scheduled_dose.dart
  providers/
    auth_provider.dart
  services/
    auth_service.dart
    firestore_service.dart
    medicine_reminder_service.dart
    medicine_notification_service.dart
    storage_service.dart
  screens/
    auth/
      login_screen.dart
      register_screen.dart
    patient/
      patient_dashboard.dart
      medicine_reminder_screen.dart
      medicine_form_screen.dart
      profile_screen.dart
      record_form_screen.dart
      record_detail_screen.dart
    doctor/
      doctor_dashboard.dart
    admin/
      admin_dashboard.dart
    common/
      loading_screen.dart
  utils/
    constants.dart
    validators.dart
```

## Setup steps

### 1) Open the existing Flutter app root

The downloaded workspace can contain an outer `meditrack-main` folder and the
actual Flutter project nested inside it. Run Flutter commands from the folder
that contains `pubspec.yaml`. If your terminal is in the outer folder, use:

```powershell
Set-Location .\meditrack-main
flutter pub get
flutter run
```

Verify:
- `flutter doctor` shows no critical issues.
- `Get-ChildItem pubspec.yaml` finds the project manifest before running Flutter.
- The app runs with `flutter run -d edge` or `flutter run`.

### 2) Install dependencies and configure Firebase

```powershell
flutter pub get
```

The app and its reminder dependencies are already declared in `pubspec.yaml`.
Then configure Firebase for the project:

```powershell
flutterfire configure
```

The checked-in `lib/firebase_options.dart` currently contains placeholder demo
values. Until you run `flutterfire configure` for your own Firebase project, the
app deliberately uses local demo mode. After configuring, verify that the
generated options contain your project's real Firebase values and restart the
app; sign-in, patient records, attachments, and reminders will then use Firebase
Auth, Firestore, and Storage. A Firebase initialization error now stops startup
instead of silently switching to local data.

Verify:
- The generated `lib/firebase_options.dart` is created.
- `flutter analyze` shows no project-level import errors.

### 3) Enable Firebase services
In Firebase Console:
- Enable Authentication → Email/Password
- Create Firestore database
- Create Firebase Storage bucket
- Set the security rules from `firestore.rules` and `storage.rules`

Verify:
- Authentication page loads without errors.
- Firestore rules are accepted by Firebase.

### 4) Run the app and test authentication

```powershell
flutter run -d chrome
```

Verify:
- The login screen appears.
- Registering a patient or doctor creates a user in Firebase Auth and a document in `users/{uid}`.
- A deactivated user cannot log in.

### 5) Patient flows
Verify:
- Profile screen saves patient details to `patients/{uid}`.
- Add record stores data to `records/{recordId}`.
- File upload respects 5 MB and PDF/JPG/PNG restrictions.
- History list displays sorted records.

In demo mode, records and attachment metadata persist locally on that device
between app launches. Demo data is not uploaded or synchronized to Firebase or
other devices. Firebase cloud persistence requires configuring your Firebase
project as described above.

### 6) Smart Medical Reports (Flask + MySQL + Flutter)

The Smart Medical Report Management module provides a complete end-to-end healthcare system for managing medical documents across Flutter, Python Flask, and MySQL.

#### Features
- **Modern Reports Dashboard**: View uploaded reports in rounded cards with custom healthcare category icons (Blood test, Urine test, X-ray, MRI, CT, Prescription, Other).
- **Search & Smart Filters**: Real-time search across report title, doctor name, and hospital. Filter by category chips, date range selector, and newest/oldest sorting.
- **Smart Grouping**: Displays reports grouped hierarchically by Category, Year, and Month (e.g. *Blood Reports -> January 2026, February 2026*).
- **Upload Form**: Allows patients to upload PDF, JPG, JPEG, and PNG files up to 5 MB with title, category, doctor, hospital, date, and notes. Displays upload progress bar and clear feedback.
- **In-App Viewing & Download**:
  - In-app PDF viewer powered by `syncfusion_flutter_pdfviewer`.
  - Image viewer with pinch-to-zoom and pan via `InteractiveViewer`.
  - Secure downloading to the device using `FileSaver`.
  - Confirmation dialog before deleting reports.
- **Medical History Integration**: Seamlessly links uploaded reports to patient visit summaries in Medical History. When viewing a medical record, associated reports appear under "Related medical reports" with direct viewer navigation and an "Attach report" option.
- **Doctor Access Authorization**: Patients explicitly grant or revoke access to doctors. Doctors can only view and download reports of patients who granted them access.

#### Python Flask Backend & MySQL Database

The backend is located in `backend/` and provides authenticated REST APIs:

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/register` | Register new Patient, Doctor, or Admin |
| `POST` | `/api/auth/login` | Authenticate and obtain JWT token |
| `GET` | `/api/auth/me` | Fetch authenticated user profile |
| `POST` | `/api/auth/grant-access` | Patient grants access to doctor ID |
| `POST` | `/api/auth/revoke-access` | Patient revokes access from doctor ID |
| `GET` | `/api/reports` | List patient reports (with search, category, date filters) |
| `POST` | `/api/reports` | Upload report with multipart file, metadata, validation |
| `GET` | `/api/reports/<id>` | Retrieve single report metadata (access restricted) |
| `PUT` | `/api/reports/<id>` | Update report metadata |
| `DELETE` | `/api/reports/<id>` | Delete report and physical file |
| `GET` | `/api/reports/<id>/download` | Stream/download report file with path traversal protection |
| `GET` | `/api/records/<id>/reports` | List reports linked to a medical history record |

#### Security Implementation
1. **File Type & Signature Validation**: File extensions are checked against an allowed whitelist (`.pdf`, `.jpg`, `.jpeg`, `.png`) AND the actual file magic bytes (`%PDF-`, `\xFF\xD8\xFF`, `\x89PNG\r\n\x1a\n`) are verified. Spoofed extensions (e.g. executable renamed to `.pdf`) are rejected.
2. **File Size Restriction**: Strictly enforces 5 MB limit.
3. **Randomized Secure Storage**: Uploaded files are assigned random UUID filenames (`uuid.uuid4().hex + ext`) and stored in patient-isolated directories.
4. **No Direct Static URL Exposure**: Files are never served as static public URLs; downloads require a valid JWT token through `/api/reports/<id>/download`.
5. **Path Traversal Protection**: File paths are validated via `os.path.commonpath` to ensure they reside strictly within the configured storage directory.
6. **Authorization Isolation**: Patients can only access their own reports. Doctors can only access reports of patients who explicitly granted them access.

#### Running the Flask Backend & MySQL

1. Install Python dependencies:
```powershell
pip install -r backend/requirements.txt
```

2. (Optional) Configure MySQL:
To connect to MySQL, set the `DATABASE_URL` environment variable:
```powershell
$env:DATABASE_URL="mysql+pymysql://root:yourpassword@localhost:3306/meditrack"
```
Execute the migration scripts in MySQL:
- `backend/migrations/schema.sql` (Creates database and all tables)
- `backend/migrations/migration_medical_reports.sql` (Applies reports table to existing DB)
- `backend/migrations/seed_data.sql` (Populates demo accounts and sample records)

*Note: If `DATABASE_URL` is not set, the Flask app automatically falls back to local SQLite (`backend/meditrack.db`), allowing immediate zero-configuration testing without running MySQL.*

3. Start the Flask server:
```powershell
python backend/run.py
```
The server will start at `http://127.0.0.1:5000`.

4. Run backend tests:
```powershell
cd backend
python -m pytest tests/test_reports_api.py -v
```

### 7) Doctor and admin flows
Verify:
- Doctor sees and opens records only for patients who granted access.
- Admin dashboard count totals match users/records.
- Admin can activate/deactivate or delete users.

### 8) Medicine reminders

The existing application is a Flutter + Firebase project. Medicine data follows
that architecture and is stored in the signed-in patient's
`patients/{uid}/medicines/{medicineId}` Firestore subcollection; dose records
are stored beneath each medicine in `doses/{doseId}`. In demo mode, the same
patient-scoped data is stored locally with SharedPreferences. Deploy the updated
`firestore.rules` before testing with Firebase.

To try it, sign in as a patient, select **Medicine Reminders**, then add a
medicine. For example, use `Demo medicine`, `1 tablet`, `Twice daily`, reminder
times `08:00` and `20:00`, start date today, end date seven days from today, and
`After food`. The form validates the dose count, distinct reminder times,
dates, and required fields.

On Android and iOS, allow notification permission when prompted. Reminders are
scheduled locally on the device, so a separate push-notification service is not
required. Android notifications are inexact to avoid requesting the restricted
exact-alarm permission; the operating system may delay an alert. The Android
boot receiver restores scheduled notifications after reboot. The app keeps one
stable notification identifier per dose and schedules the next 48 eligible
doses (within a 14-day schedule window); reopening the screen refreshes the
schedule. iOS itself limits pending notifications to 64.

Each dose stays pending until the patient chooses **Taken**, **Snooze 10 min**,
or **Skip**. The app never records a dose as taken automatically. A pending
dose changes to Missed when its 30-minute reminder window has elapsed. Daily
and seven-day adherence percentages use resolved doses (taken,
skipped, or missed); history shown in the app covers the most recent 30 days.

Browser notifications depend on browser permission and lifecycle behavior and
are not a substitute for reliable background push delivery. For remote push or
server-side scheduling, configure a push provider and trusted backend separately.

#### Current persistence and API boundary

There is no Flask service, MySQL connection, SQL schema, or REST API in this
repository: authentication and patient records use Firebase Auth and Firestore.
The reminder feature therefore uses the existing Firebase identity and
owner-scoped Firestore paths/rules rather than introducing an unauthenticated,
disconnected Flask/MySQL service. The Firestore operations are:

| Operation | Firestore path |
|---|---|
| Add/list/update/discontinue medicine | `patients/{uid}/medicines/{medicineId}` |
| Create/read/update dose and history | `patients/{uid}/medicines/{medicineId}/doses/{doseId}` |
| Retrieve upcoming doses/adherence | Query the signed-in patient's dose subcollections |
| Take/skip/snooze | Update the matching pending dose document |

`uid` is taken from the signed-in app user, and the nested Firestore rules
enforce ownership. Demo mode is device-local and is not shared between devices.
No MySQL migration or Flask endpoint is included because there is no corresponding
backend in this project; add those only if the project is intentionally migrated
from Firebase.

### 9) Tests

Run the reminder service tests with:

```powershell
flutter test test/medicine_reminder_service_test.dart
```

They cover patient-scoped medicine storage, deterministic dose generation,
duplicate prevention, Taken/Skipped/Snooze transitions, the 30-minute missed
window, and patient isolation. Notification delivery and permission prompts
must additionally be verified on a real or emulated device.

Run the medical report feature tests with:

```powershell
flutter test test/medical_reports_test.dart
```

They cover PDF and image signature validation, size rejection, patient-scoped
report access, metadata updates and deletion, patient-granted doctor access,
and report dashboard search, category filtering, sorting, and grouping.
Firebase Security Rules should additionally be exercised against a configured
Firebase project or the Firebase Emulator Suite.

### 10) Final checks

```powershell
flutter test
flutter analyze
```

Verify:
- Test suite passes.
- No analysis errors block the app build.

## Firebase security rules

Deploy the provided rules before using Firebase-backed records:
- `firestore.rules`
- `storage.rules`

The doctor patient lookup index is in `firestore.indexes.json`. Review and test
rules against your Firebase project before production deployment.

## Notes
- Admin account must be created manually in Firebase Console.
- `isActive` must be true for login.
- Replace placeholder Firebase config values with the values generated by `flutterfire configure`.
- In demo mode, accounts, profiles, and the current login are stored on the device; they are not synced to Firebase or other devices.
