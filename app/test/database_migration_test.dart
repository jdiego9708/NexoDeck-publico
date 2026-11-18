import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/database.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexodeck_migration');
    file = File('${dir.path}/nexodeck.sqlite');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<NexoDeckDatabase> open() async {
    final db = NexoDeckDatabase.forTesting(NativeDatabase(file));
    // Cualquier consulta fuerza la apertura, y con ella onCreate/onUpgrade.
    await db.select(db.devices).get();
    return db;
  }

  test('una base nueva queda en la version actual del esquema', () async {
    final db = await open();
    final version = await db
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();
    expect(version, db.schemaVersion);
    await db.close();
  });

  // Reproduce el estado real encontrado en el equipo principal: el ALTER de
  // una migracion ya corrio pero `user_version` quedo atras, porque el PC se
  // apago en el medio. Sin `_addColumnIfMissing`, el siguiente arranque
  // reintenta el mismo ALTER, muere con "duplicate column name" y la app no
  // vuelve a abrir nunca -- sin ninguna salida para el usuario.
  test('una migracion a medias no deja la base inabrible', () async {
    final first = await open();
    await first.customStatement(
      'INSERT INTO app_settings (key, value) VALUES (?, ?)',
      ['centinela', 'sigo-aca'],
    );
    // Las columnas ya estan; solo se retrocede la version.
    await first.customStatement('PRAGMA user_version = 5');
    await first.close();

    final second = await open();
    final version = await second
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();
    expect(version, second.schemaVersion);

    // Y el reintento de la migracion no se lleva puestos los datos.
    final sentinel = await second
        .customSelect("SELECT value FROM app_settings WHERE key = 'centinela'")
        .map((row) => row.read<String>('value'))
        .getSingle();
    expect(sentinel, 'sigo-aca');
    await second.close();
  });
}
