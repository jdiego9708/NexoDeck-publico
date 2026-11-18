---
name: drift-migration
description: Cómo crear/versionar migraciones de la base de datos Drift del proyecto.
---

# drift-migration

Las 11 tablas del esquema completo ya existen en `schemaVersion 1`
(`app/lib/data/local/tables/`, unidas en `app/lib/data/local/database.dart`).
Decisión ya implementada del usuario: todo el esquema de una vez, no
incremental por fase.

## Agregar una columna o tabla nueva (bump de schemaVersion)

1. Edita la tabla en `app/lib/data/local/tables/*.dart` (o crea un archivo
   nuevo para una tabla nueva, y registrala en `tables:` de
   `@DriftDatabase` en `database.dart`).
2. Sube `schemaVersion` en `NexoDeckDatabase`.
3. Agrega un bloque `if (from < N) { ... }` dentro de `onUpgrade` en
   `MigrationStrategy` con los `ALTER TABLE`/`CREATE TABLE` necesarios
   (`m.addColumn(...)`, `m.createTable(...)`, etc. — ver la API de
   `Migrator` en `drift`).
4. Regenera: `dart run build_runner build --delete-conflicting-outputs`
   (desde `app/`). El flag `--delete-conflicting-outputs` en la práctica ya
   no hace nada en esta versión de build_runner (aparece como warning
   ignorado) pero no rompe nada dejarlo.
5. Corre `flutter analyze` y prueba `flutter run -d windows` con una copia
   vieja de la base de datos para confirmar que la migración corre sin
   perder datos.

## Gotchas ya encontrados en este proyecto

- **Nombra las tablas con cuidado.** La tabla de acciones es `ActionsTable`,
  NO `Actions` — colisiona con `package:flutter/widgets.dart`. Revisa que
  el nombre de cualquier tabla nueva no choque con algo de Flutter/Dart core.
- **`autoIncrement()` y `primaryKey` override son mutuamente excluyentes.**
  `autoIncrement()` ya declara la PK; no agregues
  `@override Set<Column> get primaryKey => {id};` encima (drift_dev lo
  rechaza). Ver `tables/hardware_history_table.dart`.
- **Dos FKs a la misma tabla necesitan `@ReferenceName`.** Si una tabla
  tiene mas de una columna `references()` apuntando a la misma tabla (ej.
  `MacroSteps.macroActionId` y `MacroSteps.stepActionId`, ambas a
  `ActionsTable`), anota cada una con `@ReferenceName('algo_unico')` o
  drift_dev genera un warning de nombres duplicados y omite esa relación
  inversa de la API de "manager".
- **Nombre de la clase de datos generada:** drift_dev intenta singularizar
  el nombre de la tabla (`Profiles` -> `Profile`, `AlertRules` ->
  `AlertRule`). Si el nombre de tabla no termina en una `s` "normal"
  (ej. `ActionsTable`, `HardwareHistory`), el resultado es
  `<NombreTabla>Data` (`ActionsTableData`, `HardwareHistoryData`). Antes de
  escribir código que referencia el tipo generado, corre el build una vez
  y confirma el nombre real en el archivo `.g.dart`.
- **`foreign_keys` no esta prendido por defecto en sqlite3.** Sin
  `PRAGMA foreign_keys = ON` en `beforeOpen`, los `onDelete: KeyAction.cascade`
  de las tablas no hacen nada en runtime. Ya esta en
  `database.dart::migration`, no lo borres.
- **`update(table).replace(entity)` resetea columnas ausentes del
  companion a null/default** (no es un update parcial). Para actualizar
  solo algunos campos, usa `(update(table)..where(...)).write(companion)`
  en su lugar. Ver `daos/devices_dao.dart::setAuthorized`.
- **Inspeccionar la base de datos real:** ver la nota en `CLAUDE.md` raíz
  (ruta redirigida de Documentos, no hay `sqlite3` CLI, usar un script Dart
  con `package:sqlite3` corrido desde dentro de `app/`).
