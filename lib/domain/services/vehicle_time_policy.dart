import '../../core/constants/business_constants.dart';

class VehicleTimePolicy {
  const VehicleTimePolicy();

  DateTime warningAt(DateTime createdAt) => createdAt.add(BusinessConstants.warningAfter);
  DateTime alarmAt(DateTime createdAt) => createdAt.add(BusinessConstants.alarmAfter);
}
