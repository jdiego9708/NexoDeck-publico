import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/data/local/daos/window_layouts_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/window_layouts_table.dart';
import 'package:nexodeck/features/compact_overlay/data/window_layout_repository.dart';

void main() {
  late NexoDeckDatabase db;
  late WindowLayoutRepository repository;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    repository = WindowLayoutRepository(
      WindowLayoutsDao(db),
      AppSettingsDao(db),
    );
  });

  tearDown(() => db.close());

  test('getLayout devuelve null cuando nunca se guardo nada', () async {
    expect(await repository.getLayout(WindowMode.compact), isNull);
  });

  test('saveLayout actualiza en vez de duplicar filas para el mismo modo', () async {
    await repository.saveLayout(
      WindowMode.compact,
      posX: 10,
      posY: 20,
      width: 320,
      height: 460,
      alwaysOnTop: true,
    );
    await repository.saveLayout(
      WindowMode.compact,
      posX: 99,
      posY: 88,
      width: 350,
      height: 500,
      alwaysOnTop: true,
    );

    final layout = await repository.getLayout(WindowMode.compact);
    expect(layout, isNotNull);
    expect(layout!.posX, 99);
    expect(layout.posY, 88);
    expect(layout.width, 350);
    expect(layout.height, 500);

    // Una sola fila para `compact`, no dos -- confirma que el upsert por
    // `mode` reusa el id existente en vez de insertar de nuevo.
    final rows = await db.select(db.windowLayouts).get();
    expect(rows.where((r) => r.mode == WindowMode.compact), hasLength(1));
  });

  test('compact y fullscreen se guardan como filas independientes', () async {
    await repository.saveLayout(
      WindowMode.compact,
      posX: 0,
      posY: 0,
      width: 320,
      height: 460,
    );
    await repository.saveLayout(
      WindowMode.fullscreen,
      posX: 100,
      posY: 100,
      width: 1100,
      height: 750,
    );

    final rows = await db.select(db.windowLayouts).get();
    expect(rows, hasLength(2));
  });

  test('recuerda el ultimo modo activo entre reinicios', () async {
    expect(await repository.getLastActiveMode(), WindowMode.fullscreen);

    await repository.setLastActiveMode(WindowMode.compact);

    expect(await repository.getLastActiveMode(), WindowMode.compact);
  });
}
