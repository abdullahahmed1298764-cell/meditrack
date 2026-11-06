class AppValidators {
  static String? validateRequired(String? value, {String fieldName = 'Field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required.';
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.length < 6) {
      return 'Password must be at least 6 characters long.';
    }
    return null;
  }

  static String? validateAge(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Age is required.';
    final age = int.tryParse(trimmed);
    if (age == null || age < 0 || age > 120) {
      return 'Enter a valid age between 0 and 120.';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Phone number is required.';
    if (trimmed.length < 10) return 'Enter a valid phone number.';
    return null;
  }
}
