class VinValidator {
  static final RegExp _allowedPattern = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static final RegExp _invalidCharactersPattern = RegExp(r'[IOQ]');

  const VinValidator._();

  static String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static VinValidationResult validate(String value) {
    final normalized = normalize(value);
    if (normalized.length != 17) {
      return VinValidationResult.invalid(normalized, 'VIN musi mieć dokładnie 17 znaków.');
    }
    if (_invalidCharactersPattern.hasMatch(normalized)) {
      return VinValidationResult.invalid(normalized, 'VIN nie może zawierać liter I, O ani Q.');
    }
    if (!_allowedPattern.hasMatch(normalized)) {
      return VinValidationResult.invalid(normalized, 'VIN może zawierać tylko cyfry i wielkie litery.');
    }
    return VinValidationResult.valid(normalized);
  }
}

class VinValidationResult {
  const VinValidationResult._({required this.normalizedVin, required this.isValid, this.errorMessage});

  factory VinValidationResult.valid(String normalizedVin) => VinValidationResult._(normalizedVin: normalizedVin, isValid: true);
  factory VinValidationResult.invalid(String normalizedVin, String errorMessage) => VinValidationResult._(normalizedVin: normalizedVin, isValid: false, errorMessage: errorMessage);

  final String normalizedVin;
  final bool isValid;
  final String? errorMessage;
}
