class AppConstants {
  static const String appName = 'Meditrack';
  static const String patientRole = 'Patient';
  static const String doctorRole = 'Doctor';
  static const String adminRole = 'Admin';

  static const List<String> roles = [patientRole, doctorRole, adminRole];
  static const int maxUploadSizeInBytes = 5 * 1024 * 1024;
  static const List<String> allowedDocumentMimeTypes = <String>[
    'application/pdf',
    'image/jpeg',
    'image/png',
  ];
}
