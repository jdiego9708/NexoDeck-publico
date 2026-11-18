// Script de diagnostico, no codigo de la app: imprime por stdout (es su
// unica salida) y usa `sqlite3` directo, que llega como dependencia
// transitiva de Drift.
// ignore_for_file: avoid_print, depend_on_referenced_packages

// Siembra (o borra) el escenario de prueba del E2E de macros y parametros
// en una base de NexoDeck: una accion parametrizada con un `select`, dos
// acciones que comparten la variable `{{rama}}`, y una macro que las
// encadena con una pausa.
//
// Existe porque el E2E real hay que dispararlo desde el TELEFONO (tocar la
// tarjeta, cargar el prompt) y del lado PC no hay automatizacion de UI que
// permita crear las acciones con clics -- ver CLAUDE.md. Se siembra
// directo en la base y se levanta la app despues.
//
// Se corre DESDE `app/`:
//   dart run tool/seed_macro_e2e.dart <ruta.sqlite> seed [<archivo-testigo>]
//   dart run tool/seed_macro_e2e.dart <ruta.sqlite> clean
//
// **La app tiene que estar cerrada**: Drift no se entera de escrituras
// hechas por fuera de su propia conexion, asi que con la app abierta los
// cambios no aparecen hasta reiniciarla.
//
// Que verifica cada pieza, una vez sembrado:
// - `E2E Parametros`: el telefono debe PREGUNTAR (texto + desplegable con
//   opciones) y la PC dejar el resultado en el portapapeles.
// - `E2E Macro`: el prompt debe pedir `rama` y `tag` -- DOS campos, no
//   tres: los dos pasos comparten `rama` y se deduplica. Al correr, el paso
//   1 escribe en el archivo testigo y el paso 2 pisa el portapapeles, con
//   1.5s de pausa en el medio.
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'uso: dart run tool/seed_macro_e2e.dart <ruta.sqlite> seed|clean '
      '[<archivo-testigo>]',
    );
    exit(64);
  }

  final db = sqlite3.open(args[0]);
  // **Obligatorio, y no es decorativo**: SQLite trae las claves foraneas
  // APAGADAS por defecto. La app las prende en el `beforeOpen` de Drift,
  // pero este script abre la base por su cuenta, asi que sin esta linea el
  // `clean` borra las acciones y deja huerfanas sus filas de
  // `action_parameters` y `macro_steps` (el `onDelete: cascade` no corre).
  // Ya paso.
  db.execute('PRAGMA foreign_keys = ON');
  try {
    switch (args[1]) {
      case 'clean':
        // Se borra tabla por tabla en vez de confiar solo en el cascade:
        // asi el limpiado tambien repara una base que quedo con huerfanas
        // de una corrida anterior (que es lo que paso cuando este script
        // todavia no prendia las claves foraneas).
        db.execute("delete from macro_steps where id like 'e2e-%'");
        db.execute("delete from action_parameters where id like 'e2e-%'");
        db.execute("delete from actions_table where id like 'e2e-%'");
        print('escenario E2E borrado');
      case 'seed':
        final witness = args.length > 2
            ? args[2]
            : '${Directory.systemTemp.path}${Platform.pathSeparator}'
                  'nexodeck_e2e_macro.txt';
        _seed(db, witness);
        print('escenario E2E sembrado (testigo: $witness)');
        for (final row in db.select(
          "select id, name, action_type from actions_table where id like 'e2e-%'",
        )) {
          print('  $row');
        }
      default:
        stderr.writeln('modo desconocido: ${args[1]} (esperaba seed|clean)');
        exit(64);
    }
  } finally {
    db.close();
  }
}

void _seed(Database db, String witnessFile) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void action(
    String id,
    String name,
    String type,
    String? template, {
    String icon = 'bolt',
    String color = '#6366F1',
    int showWindow = 1,
    String? terminalType,
  }) {
    db.execute(
      'insert or replace into actions_table '
      '(id, name, description, icon, color_hex, action_type, command_template, '
      'requires_admin, terminal_type, is_favorite, created_at, updated_at, '
      'group_id, show_terminal_window) '
      'values (?,?,null,?,?,?,?,0,?,0,?,?,null,?)',
      [id, name, icon, color, type, template, terminalType, now, now, showWindow],
    );
  }

  void param(
    String id,
    String actionId,
    String key,
    String label, {
    String inputType = 'text',
    String? defaultValue,
    String? optionsJson,
    int order = 0,
  }) {
    db.execute(
      'insert or replace into action_parameters '
      '(id, action_id, key, label, input_type, default_value, options_json, '
      'order_index) values (?,?,?,?,?,?,?,?)',
      [id, actionId, key, label, inputType, defaultValue, optionsJson, order],
    );
  }

  void step(String id, String macroId, String stepId, int order, int delayMs) {
    db.execute(
      'insert or replace into macro_steps '
      '(id, macro_action_id, step_action_id, order_index, delay_ms_after) '
      'values (?,?,?,?,?)',
      [id, macroId, stepId, order, delayMs],
    );
  }

  // Accion parametrizada simple. Es `clipboard` a proposito: el efecto se
  // verifica leyendo el portapapeles de la PC (`Get-Clipboard`), sin
  // depender de que se vea una ventana.
  action(
    'e2e-param',
    'E2E Parametros',
    'clipboard',
    'msg=[{{mensaje}}] env=[{{entorno}}]',
    icon: 'content_paste',
    color: '#EF4444',
  );
  param(
    'e2e-param-p1',
    'e2e-param',
    'mensaje',
    'Mensaje',
    defaultValue: 'hola',
  );
  param(
    'e2e-param-p2',
    'e2e-param',
    'entorno',
    'Entorno',
    inputType: 'select',
    optionsJson: '["staging","produccion"]',
    order: 1,
  );

  // Paso 1: terminal sin ventana, deja rastro en el archivo testigo. Hace
  // falta porque el paso 2 pisa el portapapeles: sin el archivo no habria
  // forma de probar que el paso 1 tambien corrio.
  action(
    'e2e-paso1',
    'E2E Paso 1',
    'terminal',
    'echo paso1 rama=[{{rama}}] >> "$witnessFile"',
    icon: 'terminal',
    showWindow: 0,
    terminalType: 'cmd',
  );
  param('e2e-paso1-p1', 'e2e-paso1', 'rama', 'Rama', defaultValue: 'main');

  action(
    'e2e-paso2',
    'E2E Paso 2',
    'clipboard',
    'paso2 rama=[{{rama}}] tag=[{{tag}}]',
    icon: 'content_paste',
  );
  // MISMA key `rama` que el paso 1: es lo que ejercita el dedupe del
  // prompt (`promptParametersFor`).
  param('e2e-paso2-p1', 'e2e-paso2', 'rama', 'Rama');
  param('e2e-paso2-p2', 'e2e-paso2', 'tag', 'Tag', defaultValue: 'v1', order: 1);

  action(
    'e2e-macro',
    'E2E Macro',
    'macro',
    null,
    icon: 'playlist_play',
    color: '#10B981',
  );
  step('e2e-macro-s1', 'e2e-macro', 'e2e-paso1', 0, 1500);
  step('e2e-macro-s2', 'e2e-macro', 'e2e-paso2', 1, 0);
}
