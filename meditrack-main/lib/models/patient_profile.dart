class PatientProfile {
  final String uid;
  final int age;
  final String gender;
  final String phone;
  final String emergencyContactName;
  final String emergencyContactPhone;

  PatientProfile({
    required this.uid,
    required this.age,
    required this.gender,
    required this.phone,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
  });

  factory PatientProfile.fromMap(String uid, Map<String, dynamic> data) {
    return PatientProfile(
      uid: uid,
      age: int.tryParse((data['age'] ?? '0').toString()) ?? 0,
      gender: (data['gender'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      emergencyContactName: (data['emergencyContactName'] ?? '').toString(),
      emergencyContactPhone: (data['emergencyContactPhone'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'age': age,
      'gender': gender,
      'phone': phone,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
    };
  }
}
