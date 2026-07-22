import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Operators extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class ActiveVehicles extends Table {
  TextColumn get id => text()();
  TextColumn get vin => text().unique()();
  TextColumn get operatorId => text().references(Operators, #id)();
  TextColumn get location => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get warningAt => dateTime()();
  DateTimeColumn get alarmAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class VehicleHistory extends Table {
  TextColumn get id => text()();
  TextColumn get vin => text()();
  TextColumn get operatorId => text()();
  TextColumn get location => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get warningAt => dateTime()();
  DateTimeColumn get alarmAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get completedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class AuditLogEntries extends Table {
  TextColumn get id => text()();
  TextColumn get operation => text()();
  TextColumn get entityId => text()();
  TextColumn get operatorId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Operators, ActiveVehicles, VehicleHistory, AuditLogEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
