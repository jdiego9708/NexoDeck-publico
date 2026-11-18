import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

enum AlertMetric { cpuTemp, gpuTemp, cpuUsage, gpuUsage, ramUsage, diskUsage }

enum AlertOperator { gt, lt, gte, lte }

enum NotifyTarget { local, remoteDevice, both }

class AlertRules extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  TextColumn get metric => textEnum<AlertMetric>()();
  TextColumn get operatorType => textEnum<AlertOperator>()();
  RealColumn get threshold => real()();

  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();

  TextColumn get notifyTarget =>
      textEnum<NotifyTarget>().withDefault(const Constant('both'))();

  /// Evita spam de alertas.
  IntColumn get cooldownSeconds => integer().withDefault(const Constant(60))();

  @override
  Set<Column> get primaryKey => {id};
}
