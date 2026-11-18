import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/ai_assistant/domain/chat_destination.dart';

ChatDestination _local(String id, {bool available = true}) =>
    ChatDestination.local(modelId: id, label: id, available: available);

void main() {
  group('los ids no pueden colisionar entre tipos', () {
    /// Un modelo de Ollama y uno descargado pueden llamarse igual. Si el id
    /// fuera solo el nombre, el destino por defecto no podria decir cual era.
    test('the same model name in two kinds yields two different ids', () {
      expect(
        _local('qwen3-14b').id,
        isNot(ChatDestination.ollama(model: 'qwen3-14b').id),
      );
    });
  });

  group('lo que se guarda son los DESACTIVADOS', () {
    /// Un modelo recien descargado tiene que aparecer sin que haya que tocarlo.
    /// Guardando la lista al reves, todo lo nuevo naceria invisible.
    test('anything unknown is enabled by default', () {
      const prefs = ChatDestinationPrefs();
      expect(prefs.isEnabled('local:recien-bajado'), isTrue);
      expect(prefs.isEnabled(kClaudeCodeDestinationId), isTrue);
    });

    test('disabling and re-enabling round trips through storage', () {
      final prefs = const ChatDestinationPrefs()
          .withEnabled('local:a', false)
          .withEnabled('local:b', false)
          .withEnabled('local:a', true);

      final restored = decodeDestinationPrefs(encodeDestinationPrefs(prefs));
      expect(restored.isEnabled('local:a'), isTrue);
      expect(restored.isEnabled('local:b'), isFalse);
    });

    /// Apagar el destino por defecto no puede dejarlo apuntando a algo apagado:
    /// el arranque siguiente no activaria nada y nada lo explicaria.
    test('disabling the default clears it', () {
      final prefs = const ChatDestinationPrefs()
          .withDefault('remote:deepseek')
          .withEnabled('remote:deepseek', false);
      expect(prefs.defaultId, isNull);
    });

    /// Y elegir por defecto algo apagado es una contradiccion: se enciende.
    test('choosing a disabled destination as default enables it', () {
      final prefs = const ChatDestinationPrefs()
          .withEnabled('remote:deepseek', false)
          .withDefault('remote:deepseek');
      expect(prefs.isEnabled('remote:deepseek'), isTrue);
      expect(prefs.defaultId, 'remote:deepseek');
    });
  });

  group('leer preferencias rotas no puede tumbar el arranque', () {
    test('garbage reads as no preferences instead of throwing', () {
      for (final raw in [null, '', 'no soy json', '[]', '{"disabled":5}']) {
        final prefs = decodeDestinationPrefs(raw);
        expect(prefs.defaultId, isNull);
        expect(prefs.isEnabled('lo-que-sea'), isTrue);
      }
    });
  });

  group('que se activa al arrancar', () {
    final remoto = ChatDestination.remote(
      providerId: 'deepseek',
      label: 'DeepSeek',
      model: 'deepseek-chat',
      available: true,
    );

    test('the saved default wins when it still works', () {
      final elegido = resolveStartupDestination([
        ChatDestination.correspondent,
        remoto,
      ], const ChatDestinationPrefs().withDefault(remoto.id));
      expect(elegido?.id, remoto.id);
    });

    /// **El caso que se vio en el S24.** Un destino guardado que ya no existe
    /// (modelo borrado, clave olvidada) no puede dejar el asistente inactivo
    /// sin explicacion: se cae al siguiente que sirva.
    test('a saved default that no longer works falls back', () {
      final elegido = resolveStartupDestination([
        ChatDestination.correspondent,
      ], const ChatDestinationPrefs().withDefault('remote:borrado'));
      expect(elegido?.id, kClaudeCodeDestinationId);
    });

    /// Un modelo local puede tardar y comerse la VRAM, asi que nunca se elige
    /// solo: el usuario tiene que pedirlo.
    test('a local model is never auto-selected without being the default', () {
      final elegido = resolveStartupDestination([
        _local('qwen3-14b'),
      ], const ChatDestinationPrefs());
      expect(elegido, isNull);
    });

    test('but it is honoured when the user did choose it', () {
      final local = _local('qwen3-14b');
      final elegido = resolveStartupDestination([
        local,
      ], const ChatDestinationPrefs().withDefault(local.id));
      expect(elegido?.id, local.id);
    });

    test('a disabled or unavailable destination is never chosen', () {
      expect(
        resolveStartupDestination([
          remoto,
        ], const ChatDestinationPrefs().withEnabled(remoto.id, false)),
        isNull,
      );

      final sinClave = ChatDestination.remote(
        providerId: 'openai',
        label: 'OpenAI',
        model: 'gpt',
        available: false,
      );
      expect(
        resolveStartupDestination([
          sinClave,
        ], const ChatDestinationPrefs().withDefault(sinClave.id)),
        isNull,
      );
    });

    test('nothing usable yields null instead of guessing', () {
      expect(
        resolveStartupDestination(const [], const ChatDestinationPrefs()),
        isNull,
      );
    });
  });

  group('remoteDestinationLabel', () {
    test('la pasarela local se llama «Pasarela NexoDeck»', () {
      for (final url in ['http://127.0.0.1:8888', 'http://localhost:8888']) {
        expect(
          remoteDestinationLabel(
            displayName: 'Otro (proxy propio)',
            baseUrl: url,
            model: 'auto',
          ),
          'Pasarela NexoDeck',
        );
      }
    });

    test('un servicio por internet lleva modelo (Proveedor)', () {
      expect(
        remoteDestinationLabel(
          displayName: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-flash',
        ),
        'deepseek-flash (DeepSeek)',
      );
    });
  });
}
