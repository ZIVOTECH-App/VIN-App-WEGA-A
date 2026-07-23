import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wega_vin_timer/theme/wega_theme.dart';

void main() {
  group('WegaTheme', () {
    test('light theme uses WEGA-A red seed and Material 3', () {
      final theme = WegaTheme.light;

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, isNot(equals(Colors.blue)));
    });

    test('dark theme uses dark brightness and Material 3', () {
      final theme = WegaTheme.dark;

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
    });
  });
}
