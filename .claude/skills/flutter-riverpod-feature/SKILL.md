---
name: flutter-riverpod-feature
description: Scaffolding de una feature nueva en app/lib/features (provider + repo + UI) siguiendo el patrón Riverpod 3 del proyecto.
---

# flutter-riverpod-feature

Dos ejemplos reales:
- `app/lib/features/dashboard/` -- solo `domain/application/presentation`,
  consume un `Stream` del bridge directo, sin persistencia.
- `app/lib/features/actions/` -- las 4 capas completas (`domain/application/
  data/presentation`), con CRUD sobre Drift + ejecucion via el bridge. Usa
  este como plantilla para cualquier feature nueva que necesite guardar
  datos.

```
features/<nombre>/
├── domain/          # entidades puras Dart, sin depender de Drift ni del bridge
│   └── <entidad>.dart      # factory `.fromRow(...)` / `.fromBridge(...)` para mapear
├── data/            # solo si hay persistencia -- repositorio que envuelve DAOs de Drift
│   └── <nombre>_repository.dart
├── application/      # providers Riverpod
│   └── <algo>_provider.dart
└── presentation/
    ├── <nombre>_screen.dart
    └── widgets/
```

## IMPORTANTE: Riverpod sin codegen (`@riverpod`) -- pero Drift SÍ con codegen

`riverpod_generator` no resuelve en este SDK de Flutter (ver nota en
`CLAUDE.md` raíz — conflicto de version de `analyzer`/`meta`). Escribe
providers a mano con la API clasica:

```dart
final xProvider = StreamProvider.autoDispose<X>((ref) {
  return bridge.watchX().map(X.fromBridge);
});
```

No uses `@riverpod`/`part '..._provider.g.dart'` para providers.

**Esto NO aplica a Drift** — `drift_dev`/`build_runner` si funcionan (es un
conflicto especifico de `riverpod_generator`, no un bloqueo general de
codegen en este proyecto). Las tablas y DAOs de Drift si usan `part` +
codegen normalmente, ver `drift-migration` skill.

## Pasos para una feature nueva

1. `domain/`: entidad inmutable. Si viene del bridge FFI, factory
   `fromBridge(bridge.Tipo)` (convierte `BigInt` a `int`/`double` donde
   aplique). Si viene de Drift, factory `fromRow(TablaData row)`.
2. `data/` (solo si hay persistencia): un repositorio que recibe los DAOs
   de Drift por constructor (no un singleton global) y expone metodos a
   nivel de dominio (`watchAll()`, `createX(...)`, `execute(...)`) --
   nunca expone tipos de Drift (`Companion`, `TableData`) fuera de esta capa.
3. `application/`: un provider por cada fuente de datos reactiva.
   `Provider` para el repositorio (inyecta `databaseProvider` de
   `core/di/database_provider.dart`), `StreamProvider.autoDispose` para
   los datos que consume la UI.
4. `presentation/`: un `ConsumerWidget` que hace `ref.watch(xProvider)` y
   maneja `AsyncValue.when(data, loading, error)`. Formularios de
   crear/editar van en su propio archivo (`*_editor_sheet.dart`), abiertos
   con `showModalBottomSheet`/`showDialog` -- no metas el formulario en el
   mismo widget que la lista.
5. Registra la pantalla en `main.dart` (todavia no hay `go_router` -- una
   `NavigationBar` con `IndexedStack` alcanza para pocas pantallas; se
   agrega `go_router` cuando haga falta navegacion mas profunda o
   deep-linking).
