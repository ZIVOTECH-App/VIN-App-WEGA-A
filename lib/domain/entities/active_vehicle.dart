enum VehicleStatus { active, warning, alarm, completed }

class ActiveVehicle {
  const ActiveVehicle({
    required this.id,
    required this.vin,
    required this.operatorId,
    required this.location,
    required this.note,
    required this.createdAt,
    required this.warningAt,
    required this.alarmAt,
    required this.status,
    this.completedAt,
  });

  final String id;
  final String vin;
  final String operatorId;
  final String location;
  final String note;
  final DateTime createdAt;
  final DateTime warningAt;
  final DateTime alarmAt;
  final VehicleStatus status;
  final DateTime? completedAt;
}
