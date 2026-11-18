// Script de diagnostico, no codigo de la app: imprime por stdout (es su
// unica salida) y usa `sqlite3` directo, que llega como dependencia
// transitiva de Drift.
// ignore_for_file: avoid_print, depend_on_referenced_packages

// Diagnostico generico: vuelca las tablas que se le pidan de una base de
// NexoDeck. Se corre DESDE `app/` para que resuelva el `pubspec.yaml`
// correcto -- ver la nota de CLAUDE.md sobre inspeccionar la base real (la
// ruta cambia por maquina y por usuario, nunca hardcodearla).
//
//   dart run tool/dump_table.dart <ruta.sqlite> window_layouts app_settings
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('uso: dart run tool/dump_table.dart <ruta.sqlite> <tabla>...');
    exit(64);
  }

  final db = sqlite3.open(args.first, mode: OpenMode.readOnly);
  try {
    for (final table in args.skip(1)) {
      final exists = db.select(
        "select name from sqlite_master where type='table' and name=?",
        [table],
      );
      if (exists.isEmpty) {
        print('(sin tabla $table)');
        continue;
      }
      print('--- $table ---');
      for (final row in db.select('select * from $table')) {
        print(row);
      }
    }
  } finally {
    db.close();
  }
}
