import 'package:flutter_test/flutter_test.dart';
import 'package:wega_vin_timer/domain/services/active_vehicle_policy.dart';
import 'package:wega_vin_timer/domain/services/vehicle_time_policy.dart';

void main() {
  test('calculates warning and alarm times', () {
    final policy = VehicleTimePolicy();
    final createdAt = DateTime.utc(2026, 7, 22, 10);
    expect(policy.warningAt(createdAt), DateTime.utc(2026, 7, 22, 10, 35));
    expect(policy.alarmAt(createdAt), DateTime.utc(2026, 7, 22, 10, 40));
  });

  test('blocks more than 100 active vehicles', () {
    final policy = ActiveVehiclePolicy();
    expect(policy.canAddVehicle(activeVehicleCount: 99), isTrue);
    expect(policy.canAddVehicle(activeVehicleCount: 100), isFalse);
  });

  test('blocks duplicate active VIN', () {
    final policy = ActiveVehiclePolicy();
    expect(policy.isDuplicateActiveVin(vin: '1HGCM82633A004352', activeVins: ['1HGCM82633A004352']), isTrue);
  });
}
