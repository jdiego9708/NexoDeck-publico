// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hardware_history_dao.dart';

// ignore_for_file: type=lint
mixin _$HardwareHistoryDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $HardwareHistoryTable get hardwareHistory => attachedDatabase.hardwareHistory;
  HardwareHistoryDaoManager get managers => HardwareHistoryDaoManager(this);
}

class HardwareHistoryDaoManager {
  final _$HardwareHistoryDaoMixin _db;
  HardwareHistoryDaoManager(this._db);
  $$HardwareHistoryTableTableManager get hardwareHistory =>
      $$HardwareHistoryTableTableManager(
        _db.attachedDatabase,
        _db.hardwareHistory,
      );
}
