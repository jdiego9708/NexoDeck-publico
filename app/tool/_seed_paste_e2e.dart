// Siembra (y limpia) una accion de portapapeles con `paste_to_active_window`
// para probar el pegado de punta a punta. Temporal: no va al repo.
import 'package:sqlite3/sqlite3.dart';

const _id = 'e2e-paste-action';
const _text = 'NEXODECK PEGADO OK 4711';

void main(List<String> args) {
  final db = sqlite3.open(args[0]);
  final mode = args.length > 1 ? args[1] : 'seed';
  if (mode == 'clean') {
    db.execute('DELETE FROM actions_table WHERE id = ?', [_id]);
    print('limpiado');
  } else {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    db.execute('DELETE FROM actions_table WHERE id = ?', [_id]);
    db.execute(
      'INSERT INTO actions_table (id, name, description, icon, color_hex, '
      'action_type, command_template, requires_admin, show_terminal_window, '
      'paste_to_active_window, is_favorite, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 1, 0, ?, ?)',
      [_id, 'E2E Pegar', 'prueba de pegado', 'bolt', '#22C55E', 'clipboard',
        _text, now, now],
    );
    print('sembrado: $_text');
  }
  for (final row in db.select(
      'SELECT id, name, action_type, paste_to_active_window FROM actions_table')) {
    print(row);
  }
  db.dispose();
}
