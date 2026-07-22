import 'package:flutter_test/flutter_test.dart';
import 'package:wega_vin_timer/core/validation/vin_validator.dart';

void main() {
  test('accepts valid 17-character VIN', () {
    final result = VinValidator.validate('1HGCM82633A004352');
    expect(result.isValid, isTrue);
  });

  test('normalizes VIN by removing spaces and uppercasing', () {
    expect(VinValidator.normalize(' 1hg cm82633a004352 '), '1HGCM82633A004352');
  });

  test('blocks forbidden I O Q characters', () {
    expect(VinValidator.validate('1HGCM82633A00435I').isValid, isFalse);
    expect(VinValidator.validate('1HGCM82633A00435O').isValid, isFalse);
    expect(VinValidator.validate('1HGCM82633A00435Q').isValid, isFalse);
  });

  test('blocks non-alphanumeric characters', () {
    expect(VinValidator.validate('1HGCM82633A00435-').isValid, isFalse);
  });
}
