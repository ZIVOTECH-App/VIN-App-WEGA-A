import '../../core/constants/business_constants.dart';

class ActiveVehiclePolicy {
  const ActiveVehiclePolicy();

  bool canAddVehicle({required int activeVehicleCount}) => activeVehicleCount < BusinessConstants.maxActiveVehicles;

  bool isDuplicateActiveVin({required String vin, required Iterable<String> activeVins}) =>
      activeVins.map((value) => value.toUpperCase()).contains(vin.toUpperCase());
}
