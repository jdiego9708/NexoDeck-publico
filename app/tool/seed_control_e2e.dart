// Script de diagnostico, no codigo de la app: imprime por stdout (es su
// unica salida) y usa `sqlite3` directo, que llega como dependencia
// transitiva de Drift.
// ignore_for_file: avoid_print, depend_on_referenced_packages

// Enciende (o apaga) el servidor de control en una base de NexoDeck, y le
// deja configurado un canal de aviso que invoca un script de bash.
//
// Existe porque el interruptor vive en un dialogo y **del lado PC no hay
// automatizacion de UI** -- ver CLAUDE.md. Sembrando la preferencia y
// levantando la app despues se verifica ademas lo que de otro modo no se
// puede comprobar: que el servidor **arranca solo** al abrir la app, en
// `main()` antes de `runApp`, sin que nadie toque el panel.
//
// Se corre DESDE `app/`:
//   dart run tool/seed_control_e2e.dart <ruta.sqlite> seed <ruta-del-script>
//   dart run tool/seed_control_e2e.dart <ruta.sqlite> show
//   dart run tool/seed_control_e2e.dart <ruta.sqlite> clean
//
// **La app tiene que estar cerrada**: Drift no se entera de escrituras hechas
// por fuera de su propia conexion, asi que con la app abierta los cambios no
// aparecen hasta reiniciarla.
//
// El token NO se toca aca, y no es un olvido: es un secreto y no vive en la
// base, sino en el directorio de datos del usuario (`control_token.txt`), del
// lado Rust. Ver la seccion "Servidor de control" de CLAUDE.md.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _enabledKey = 'control_server_enabled';
const _channelsKey = 'notify_channels';

/// Ruta corta 8.3 de Git Bash. Con la larga habria que citarla y las comillas
/// quedarian anidadas con las del `-lc`.
const _gitBash = r'C:\PROGRA~1\Git\bin\bash.exe';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'uso: dart run tool/seed_control_e2e.dart <ruta.sqlite> '
      'seed <ruta-del-script> | show | clean',
    );
    exit(64);
  }

  final db = sqlite3.open(args[0]);
  final command = args[1];

  switch (command) {
    case 'seed':
      if (args.length < 3) {
        stderr.writeln('seed necesita la ruta del script de aviso');
        exit(64);
      }
      _seed(db, args[2]);
    case 'show':
      _show(db);
    case 'clean':
      _clean(db);
    default:
      stderr.writeln('comando desconocido: $command');
      exit(64);
  }

  db.close();
}

void _seed(Database db, String scriptPath) {
  // El texto del aviso viaja por stdin y la ruta del script como `$0`: asi
  // ningun shell llega a parsear el mensaje y no hay nada que escapar. `-l`
  // fija HOME, sin lo cual el `ssh` del script no encuentra su ~/.ssh/config.
  final channel = {
    'id': 'e2e',
    'label': 'Aviso E2E',
    'program': _gitBash,
    'args': ['-lc', r'bash "$0" -', scriptPath],
    'delivery': 'stdin',
    'min_level': 'milestone',
    'timeout_secs': 60,
    'enabled': true,
  };

  _set(db, _enabledKey, 'true');
  _set(db, _channelsKey, jsonEncode([channel]));

  print('Servidor de control: encendido');
  print('Canal sembrado: ${channel['id']} -> $scriptPath');
  print('');
  print('Ahora levanta la app. El servidor arranca solo, antes del primer');
  print('frame, y el panel esta en el menu "Mas".');
}

void _show(Database db) {
  for (final key in [_enabledKey, _channelsKey]) {
    final rows = db.select(
      'SELECT value FROM app_settings WHERE key = ?',
      [key],
    );
    final value = rows.isEmpty ? '<ausente>' : rows.first['value'];
    print('$key = $value');
  }
}

void _clean(Database db) {
  db.execute('DELETE FROM app_settings WHERE key IN (?, ?)', [
    _enabledKey,
    _channelsKey,
  ]);
  // Ausente significa apagado: es lo mismo que una instalacion nueva.
  print('Preferencias del servidor de control borradas (queda apagado).');
}

void _set(Database db, String key, String value) {
  db.execute(
    'INSERT INTO app_settings (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );
}
