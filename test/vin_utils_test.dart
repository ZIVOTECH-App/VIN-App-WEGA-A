import 'package:flutter_test/flutter_test.dart';
import 'package:wega_vin_timer/main.dart';

void main() {
  group('isValidVin', () {
    test('accepts valid VIN', () {
      expect(isValidVin('1HGCM82633A004352'), isTrue);
    });

    test('accepts VIN with spaces', () {
      expect(isValidVin('1HG CM8 263 3A0 04352'), isTrue);
    });

    test('accepts VIN with hyphens', () {
      expect(isValidVin('1HG-CM8-263-3A0-04352'), isTrue);
    });

    test('rejects VIN containing I', () {
      expect(isValidVin('1HGCM82633A00435I'), isFalse);
    });

    test('rejects VIN containing O', () {
      expect(isValidVin('1HGCM82633A00435O'), isFalse);
    });

    test('rejects VIN containing Q', () {
      expect(isValidVin('1HGCM82633A00435Q'), isFalse);
    });

    test('rejects too short VIN', () {
      expect(isValidVin('1HGCM82633A00435'), isFalse);
    });

    test('rejects too long VIN', () {
      expect(isValidVin('1HGCM82633A0043529'), isFalse);
    });
  });
}
