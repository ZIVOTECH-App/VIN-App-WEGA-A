import 'package:uuid/uuid.dart';

import '../../core/validation/vin_validator.dart';
import '../../domain/entities/active_vehicle.dart';
import '../../domain/services/active_vehicle_policy.dart';
import '../../domain/services/vehicle_time_policy.dart';

class AddActiveVehicleUseCase {
  AddActiveVehicleUseCase({
    ActiveVehiclePolicy activeVehiclePolicy = const ActiveVehiclePolicy(),
    VehicleTimePolicy timePolicy = const VehicleTimePolicy(),
    Uuid uuid = const Uuid(),
  })  : _activeVehiclePolicy = activeVehiclePolicy,
        _timePolicy = timePolicy,
        _uuid = uuid;

  final ActiveVehiclePolicy _activeVehiclePolicy;
  final VehicleTimePolicy _timePolicy;
  final Uuid _uuid;

  ActiveVehicle buildVehicle({
    required String vinInput,
    required String operatorId,
    required String location,
    required String note,
    required DateTime createdAt,
    required int activeVehicleCount,
    required Iterable<String> activeVins,
    required bool operatorConfirmedVin,
  }) {
    final validation = VinValidator.validate(vinInput);
    if (!validation.isValid) throw ArgumentError(validation.errorMessage);
    if (!operatorConfirmedVin) throw ArgumentError('Operator musi potwierdzić VIN przed zapisem.');
    if (!_activeVehiclePolicy.canAddVehicle(activeVehicleCount: activeVehicleCount)) {
      throw StateError('Osiągnięto limit 100 aktywnych pojazdów.');
    }
    if (_activeVehiclePolicy.isDuplicateActiveVin(vin: validation.normalizedVin, activeVins: activeVins)) {
      throw StateError('Aktywny pojazd z tym VIN już istnieje.');
    }

    return ActiveVehicle(
      id: _uuid.v4(),
      vin: validation.normalizedVin,
      operatorId: operatorId,
      location: location,
      note: note,
      createdAt: createdAt,
      warningAt: _timePolicy.warningAt(createdAt),
      alarmAt: _timePolicy.alarmAt(createdAt),
      status: VehicleStatus.active,
    );
  }
}
