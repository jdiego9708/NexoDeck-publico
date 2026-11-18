import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';

/// Instancia unica de la base de datos para toda la app. `keepAlive: true`
/// (provider normal, no autoDispose) porque la conexion a SQLite debe vivir
/// mientras la app este abierta.
final databaseProvider = Provider<NexoDeckDatabase>((ref) {
  final db = NexoDeckDatabase();
  ref.onDispose(db.close);
  return db;
});
