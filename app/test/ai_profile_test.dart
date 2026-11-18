import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/ai_assistant/application/ai_profiles_controller.dart';
import 'package:nexodeck/features/ai_assistant/data/stack_catalog_repository.dart';
import 'package:nexodeck/features/ai_assistant/domain/ai_profile.dart';

void main() {
  group('AiProfilesConfig', () {
    test('los valores por defecto son el mapeo historico', () {
      const config = AiProfilesConfig.defaults;
      expect(config.profileA.router.source, ProfileSlotSource.stack);
      expect(config.profileA.router.model, 'router');
      expect(config.profileA.thinking.model, 'fast');
      expect(config.profileB.thinking.model, 'complex');
      expect(config.profileC.thinking.model, 'writer');
    });

    test('sobrevive a un viaje de ida y vuelta', () {
      final config = AiProfilesConfig.defaults.withProfile(
        'B',
        const AiProfileConfig(
          router: ProfileSlot(source: ProfileSlotSource.ollama, model: 'qwen'),
          thinking: ProfileSlot(
            source: ProfileSlotSource.remote,
            remoteProviderId: 'remote:B.thinking',
            remoteBaseUrl: 'https://api.deepseek.com',
            remoteModel: 'deepseek-chat',
            remoteDisplayName: 'DeepSeek',
          ),
        ),
      );

      final decoded = AiProfilesConfig.decode(config.encode());
      expect(decoded.profileB.router.source, ProfileSlotSource.ollama);
      expect(decoded.profileB.router.model, 'qwen');
      expect(decoded.profileB.thinking.source, ProfileSlotSource.remote);
      expect(decoded.profileB.thinking.remoteModel, 'deepseek-chat');
      // El perfil A no se toco.
      expect(decoded.profileA.thinking.model, 'fast');
    });

    test('el perfil C sobrevive a un viaje de ida y vuelta', () {
      final config = AiProfilesConfig.defaults.withProfile(
        'C',
        const AiProfileConfig(
          router: ProfileSlot(source: ProfileSlotSource.stack, model: 'router'),
          thinking: ProfileSlot(
            source: ProfileSlotSource.ollama,
            model: 'qwen3:14b',
          ),
        ),
      );

      final decoded = AiProfilesConfig.decode(config.encode());
      expect(decoded.profileC.thinking.source, ProfileSlotSource.ollama);
      expect(decoded.profileC.thinking.model, 'qwen3:14b');
      // Los otros dos no se tocan.
      expect(decoded.profileA.thinking.model, 'fast');
      expect(decoded.profileB.thinking.model, 'complex');
    });

    test('un JSON corrupto cae a los valores por defecto', () {
      expect(
        AiProfilesConfig.decode('{no soy json').profileA.thinking.model,
        'fast',
      );
      expect(AiProfilesConfig.decode(null).profileB.thinking.model, 'complex');
      expect(
        AiProfilesConfig.decode('{"profiles": 12}').profileA.router.model,
        'router',
      );
    });

    test('deja escribir un slot sin modelo', () {
      final config = AiProfilesConfig.defaults.withProfile(
        'A',
        const AiProfileConfig(
          router: ProfileSlot(source: ProfileSlotSource.claudeCode),
          thinking: ProfileSlot(source: ProfileSlotSource.claudeCode),
        ),
      );
      final decoded = AiProfilesConfig.decode(config.encode());
      expect(decoded.profileA.router.isClaudeCode, isTrue);
      expect(decoded.profileA.thinking.isClaudeCode, isTrue);
    });
  });

  group('stackRoleFitsSlot', () {
    test('el router es el liviano; todo lo demas es pensamiento', () {
      expect(stackRoleFitsSlot('router', 'router'), isTrue);
      expect(stackRoleFitsSlot('router', 'thinking'), isFalse);
      expect(stackRoleFitsSlot('fast', 'thinking'), isTrue);
      expect(stackRoleFitsSlot('complex', 'thinking'), isTrue);
      expect(stackRoleFitsSlot('writer', 'thinking'), isTrue);
      expect(stackRoleFitsSlot('writer', 'router'), isFalse);
    });
  });

  group('stackRolesVramGb', () {
    const vram = {'router': 4.3, 'fast': 11.2, 'complex': 10.6, 'writer': 12.0};

    test('suma roles distintos', () {
      expect(stackRolesVramGb(['router', 'fast'], vram), closeTo(15.5, 1e-9));
    });

    test('el mismo rol en los dos slots se cuenta una vez (perfil C)', () {
      expect(stackRolesVramGb(['writer', 'writer'], vram), closeTo(12.0, 1e-9));
    });

    test('los vacios y los desconocidos no suman', () {
      expect(stackRolesVramGb(['', 'lo_que_sea'], vram), 0);
    });
  });

  group('stackSelectionFitsVram', () {
    const vram = {'router': 4.3, 'fast': 11.2, 'complex': 10.6, 'writer': 12.0};
    const budget = 15.9;

    test('router + writer no caben', () {
      expect(
        stackSelectionFitsVram(
          otherStackRole: 'router',
          candidateRole: 'writer',
          vramByRole: vram,
          budgetGb: budget,
        ),
        isFalse,
      );
    });

    test('router + fast si caben', () {
      expect(
        stackSelectionFitsVram(
          otherStackRole: 'router',
          candidateRole: 'fast',
          vramByRole: vram,
          budgetGb: budget,
        ),
        isTrue,
      );
    });

    test('writer con writer (mismo rol) cabe: se sirve una vez', () {
      expect(
        stackSelectionFitsVram(
          otherStackRole: 'writer',
          candidateRole: 'writer',
          vramByRole: vram,
          budgetGb: budget,
        ),
        isTrue,
      );
    });

    test('sin presupuesto no se bloquea nada', () {
      expect(
        stackSelectionFitsVram(
          otherStackRole: 'router',
          candidateRole: 'writer',
          vramByRole: vram,
          budgetGb: 0,
        ),
        isTrue,
      );
    });

    test('un slot de otro motor (otherStackRole null) no puntua', () {
      expect(
        stackSelectionFitsVram(
          otherStackRole: null,
          candidateRole: 'writer',
          vramByRole: vram,
          budgetGb: budget,
        ),
        isTrue,
      );
    });
  });

  group('StackCatalogRepository', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nexodeck-stack-test-');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('sin profiles.json lee los valores por defecto', () async {
      final repo = StackCatalogRepository(dir.path);
      final config = await repo.readProfiles();
      expect(config.profileA.thinking.model, 'fast');
    });

    test('escribe y vuelve a leer profiles.json', () async {
      final repo = StackCatalogRepository(dir.path);
      final next = AiProfilesConfig.defaults.withProfile(
        'A',
        const AiProfileConfig(
          router: ProfileSlot(source: ProfileSlotSource.stack, model: 'router'),
          thinking: ProfileSlot(
            source: ProfileSlotSource.stack,
            model: 'complex',
          ),
        ),
      );

      expect(await repo.writeProfiles(next), isNull);
      final read = await repo.readProfiles();
      expect(read.profileA.thinking.model, 'complex');
    });

    test('un scripts dir que no existe no revienta al escribir', () async {
      final repo = StackCatalogRepository('${dir.path}/no-existe');
      final error = await repo.writeProfiles(AiProfilesConfig.defaults);
      expect(error, isNotNull);
    });

    test('lee el catalogo de roles, enriquecido y alternativas', () async {
      await File('${dir.path}/models.json').writeAsString('''
{
  "models": [
    {"role": "router", "repo": "a/b", "dir": "b", "expected_quant": "nvfp4",
     "display_name": "Router X", "notes": "nota", "size_gb": 2.5, "context": 16384}
  ],
  "alternatives": [
    {"role": "router", "repo": "c/d", "dir": "d"}
  ]
}
''');
      final repo = StackCatalogRepository(dir.path);
      final catalog = await repo.readCatalog();
      expect(catalog.length, 2);
      final main = catalog.firstWhere((m) => !m.alternative);
      expect(main.label, 'Router X');
      expect(main.sizeGb, 2.5);
      expect(main.context, 16384);
      expect(catalog.firstWhere((m) => m.alternative).label, 'c/d');
    });
  });

  group('AiProfilesState.isProfileRunnable', () {
    StackModel model(String role, String dir) => StackModel(
      role: role,
      repo: 'x/$role',
      dir: dir,
      expectedQuant: '',
      displayName: '',
      notes: '',
      sizeGb: 0,
      vramGb: 0,
      context: 0,
      alternative: false,
    );

    AiProfilesState stateWith(Set<String> installed) => AiProfilesState(
      config: AiProfilesConfig.defaults,
      catalog: [
        model('router', 'qwen3.5-4b-nvfp4'),
        model('fast', 'gemma-4-12b-awq'),
        model('complex', 'qwen3-coder-30b-reap50-nvfp4'),
        model('writer', 'qwen3.5-9b-awq'),
      ],
      detection: StackDetection(installedDirs: installed),
      loading: false,
      detected: true,
    );

    test('A y B corren; C no, si falta el writer', () {
      final state = stateWith({
        'qwen3.5-4b-nvfp4',
        'gemma-4-12b-awq',
        'qwen3-coder-30b-reap50-nvfp4',
      });
      expect(state.isProfileRunnable('A'), isTrue);
      expect(state.isProfileRunnable('B'), isTrue);
      expect(state.isProfileRunnable('C'), isFalse);
    });

    test('con el writer descargado, C tambien', () {
      final state = stateWith({'qwen3.5-4b-nvfp4', 'qwen3.5-9b-awq'});
      expect(state.isProfileRunnable('C'), isTrue);
      // B no: le falta el complejo.
      expect(state.isProfileRunnable('B'), isFalse);
    });

    test('un slot que no es del stack no bloquea el perfil', () {
      final config = AiProfilesConfig.defaults.withProfile(
        'C',
        const AiProfileConfig(
          router: ProfileSlot(source: ProfileSlotSource.stack, model: 'router'),
          thinking: ProfileSlot(source: ProfileSlotSource.claudeCode),
        ),
      );
      final state = AiProfilesState(
        config: config,
        catalog: [model('router', 'qwen3.5-4b-nvfp4')],
        detection: const StackDetection(installedDirs: {'qwen3.5-4b-nvfp4'}),
        loading: false,
        detected: true,
      );
      expect(state.isProfileRunnable('C'), isTrue);
    });
  });
}
