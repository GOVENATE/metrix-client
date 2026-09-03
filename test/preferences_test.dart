import 'package:flutter_test/flutter_test.dart';
import 'package:metrix_client/preferences.dart';

void main() {
  group('Preferences.isValidImei', () {
    test('accepts an exact 15-digit IMEI', () {
      expect(Preferences.isValidImei('490154203237518'), isTrue);
      expect(Preferences.isValidImei('123456789012345'), isTrue);
    });

    test('rejects the provisional 8-digit random identifier', () {
      // Fresh installs seed an 8-digit number; it must read as provisional.
      expect(Preferences.isValidImei('12345678'), isFalse);
    });

    test('rejects values shorter or longer than 15 digits', () {
      expect(Preferences.isValidImei('12345678901234'), isFalse); // 14
      expect(Preferences.isValidImei('1234567890123456'), isFalse); // 16
    });

    test('rejects null and empty values', () {
      expect(Preferences.isValidImei(null), isFalse);
      expect(Preferences.isValidImei(''), isFalse);
    });

    test('rejects non-digit characters even at length 15', () {
      expect(Preferences.isValidImei('49015420323751a'), isFalse);
      expect(Preferences.isValidImei('4901542 3237518'), isFalse);
      expect(Preferences.isValidImei('490154203237-18'), isFalse);
    });

    test('imeiLength is the canonical IMEI length', () {
      expect(Preferences.imeiLength, 15);
    });
  });
}
