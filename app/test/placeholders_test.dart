import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/actions/domain/placeholders.dart';

void main() {
  group('placeholdersIn', () {
    test('encuentra los placeholders de una plantilla', () {
      expect(placeholdersIn('git checkout {{rama}}'), {'rama'});
      expect(placeholdersIn('mkdir {{n}} && cd {{n}}'), {'n'});
      expect(placeholdersIn('deploy {{app}} en {{entorno}}'), {
        'app',
        'entorno',
      });
    });

    test('tolera espacios adentro de las llaves', () {
      // `{{ rama }}` es lo que alguien escribe naturalmente.
      expect(placeholdersIn('git checkout {{ rama }}'), {'rama'});
    });

    test('devuelve vacío sin placeholders', () {
      expect(placeholdersIn('git status'), isEmpty);
      expect(placeholdersIn(''), isEmpty);
      expect(placeholdersIn(null), isEmpty);
    });

    test('ignora llaves sueltas o vacías', () {
      expect(placeholdersIn('echo {no es} placeholder'), isEmpty);
      expect(placeholdersIn('echo {{}}'), isEmpty);
      expect(placeholdersIn('echo {{   }}'), isEmpty);
    });
  });

  group('undeclaredPlaceholders', () {
    test('detecta el placeholder sin parámetro declarado', () {
      // El caso real que motivó esto: una acción semilla con `{{tema}}` en
      // el texto y ningún parámetro, que se ejecutaba con el literal
      // `{{tema}}` adentro sin avisar nada.
      expect(undeclaredPlaceholders('🔴 EN VIVO — {{tema}}', const []), {
        'tema',
      });
    });

    test('no reporta nada si están todos declarados', () {
      expect(
        undeclaredPlaceholders('deploy {{app}} en {{entorno}}', [
          'app',
          'entorno',
        ]),
        isEmpty,
      );
    });

    test('un parámetro declarado de más no se reporta', () {
      // Sobra `tag`, pero eso no rompe nada: solo no se usa.
      expect(
        undeclaredPlaceholders('deploy {{app}}', ['app', 'tag']),
        isEmpty,
      );
    });

    test('ignora keys vacías del editor', () {
      // Una fila de parámetro recién agregada tiene la variable vacía.
      expect(undeclaredPlaceholders('deploy {{app}}', ['', '  ']), {'app'});
    });
  });
}
