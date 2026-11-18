import 'dart:convert';
import 'dart:io';

import '../domain/ai_profile.dart';

/// Un modelo del stack vLLM, tal como lo declara `models.json`.
///
/// Los campos enriquecidos (`displayName`, `notes`, `sizeGb`, `context`,
/// `vramGb`) son opcionales: un `models.json` viejo, con solo `role`/`repo`/
/// `dir`, se sigue leyendo y la UI cae a mostrar el `repo`.
class StackModel {
  const StackModel({
    required this.role,
    required this.repo,
    required this.dir,
    required this.expectedQuant,
    required this.displayName,
    required this.notes,
    required this.sizeGb,
    required this.vramGb,
    required this.context,
    required this.alternative,
  });

  final String role;
  final String repo;
  final String dir;
  final String expectedQuant;
  final String displayName;
  final String notes;

  /// Lo que ocupa **en disco** (lo que se descarga).
  final double sizeGb;

  /// La **huella en VRAM** al servir, en GiB (pesos + KV + activaciones). Es lo
  /// que se suma para no dejar configurar dos modelos que no caben juntos. `0`
  /// es "no se sabe", y no bloquea nada.
  final double vramGb;
  final int context;
  final bool alternative;

  String get label => displayName.isNotEmpty ? displayName : repo;
}

/// Lo que se pudo averiguar del stack en este equipo.
class StackDetection {
  const StackDetection({required this.installedDirs, this.error});

  /// Nombres de carpeta presentes en `~/models` dentro de WSL2.
  final Set<String> installedDirs;

  /// Motivo por el que no se pudo detectar (sin WSL, distro apagada...). Un
  /// fallo de deteccion no puede parecer "no hay nada descargado".
  final String? error;

  static const empty = StackDetection(installedDirs: {});
}

/// Lee y escribe los ficheros del stack vLLM (`models.json`, `profiles.json`) y
/// detecta que modelos estan descargados dentro de WSL2.
///
/// No arranca nada: escribir `profiles.json` solo cambia lo que `Start-Stack`
/// servira la proxima vez. La deteccion de descargados corre **sola al abrir la
/// pantalla de perfiles, pero no levanta WSL2**: solo mira si esta arriba y, si
/// no, lo dice (el usuario lo tiene configurado para que arranque solo con
/// funciones de IA).
class StackCatalogRepository {
  const StackCatalogRepository(this.scriptsDir);

  final String scriptsDir;

  String get _base => scriptsDir.trim().replaceAll(RegExp(r'[\\/]+$'), '');

  File get _modelsFile => File('$_base/models.json');
  File get _profilesFile => File('$_base/profiles.json');

  bool get scriptsDirExists =>
      _base.isNotEmpty && Directory(_base).existsSync();

  /// Lee el catalogo de roles. Nunca lanza: un `models.json` ilegible se lee
  /// como catalogo vacio, que es un estado del que la UI sale avisando.
  Future<List<StackModel>> readCatalog() async {
    try {
      final file = _modelsFile;
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];

      final models = <StackModel>[];
      void addAll(Object? raw, bool alternative) {
        if (raw is! List) return;
        for (final entry in raw) {
          if (entry is! Map) continue;
          final role = entry['role'];
          final repo = entry['repo'];
          final dir = entry['dir'];
          if (role is! String || repo is! String || dir is! String) continue;
          models.add(
            StackModel(
              role: role,
              repo: repo,
              dir: dir,
              expectedQuant: entry['expected_quant'] is String
                  ? entry['expected_quant'] as String
                  : '',
              displayName: entry['display_name'] is String
                  ? entry['display_name'] as String
                  : '',
              notes: entry['notes'] is String ? entry['notes'] as String : '',
              sizeGb: entry['size_gb'] is num
                  ? (entry['size_gb'] as num).toDouble()
                  : 0,
              vramGb: entry['vram_gb'] is num
                  ? (entry['vram_gb'] as num).toDouble()
                  : 0,
              context: entry['context'] is int ? entry['context'] as int : 0,
              alternative: alternative,
            ),
          );
        }
      }

      addAll(decoded['models'], false);
      addAll(decoded['alternatives'], true);
      return models;
    } catch (_) {
      return const [];
    }
  }

  /// Lee el manifiesto de perfiles. Sin fichero, el mapeo historico.
  Future<AiProfilesConfig> readProfiles() async {
    try {
      final file = _profilesFile;
      if (!await file.exists()) return AiProfilesConfig.defaults;
      return AiProfilesConfig.decode(await file.readAsString());
    } catch (_) {
      return AiProfilesConfig.defaults;
    }
  }

  /// Escribe el manifiesto que `serve-profile.sh` lee. Devuelve `null` si
  /// salio bien o el motivo si no se pudo escribir.
  Future<String?> writeProfiles(AiProfilesConfig config) async {
    if (!scriptsDirExists) {
      return 'No encuentro la carpeta del stack: "$scriptsDir". '
          'Configurala con el engranaje del switch de modo.';
    }
    try {
      await _profilesFile.writeAsString(config.encode());
      return null;
    } catch (error) {
      return 'No se pudo escribir profiles.json: $error';
    }
  }

  /// Que carpetas hay en `~/models` dentro de WSL2.
  ///
  /// **Solo en Windows**, y dibujar la pantalla no puede levantar WSL2: primero
  /// mira el estado de la distro; si esta apagada no la arranca y lo dice, en
  /// vez de encenderla solo por mirar.
  Future<StackDetection> detectInstalled({required String distro}) async {
    if (!Platform.isWindows) {
      return const StackDetection(
        installedDirs: {},
        error:
            'La deteccion de modelos del stack solo funciona en Windows (WSL2).',
      );
    }
    try {
      final running = await _distroRunning(distro);
      if (!running) {
        return const StackDetection(
          installedDirs: {},
          error:
              'WSL2 no esta arrancado. Se levanta solo al activar un perfil.',
        );
      }
      final result = await Process.run(
        'wsl.exe',
        ['-d', distro, '-e', 'bash', '-lc', 'ls -1 ~/models 2>/dev/null'],
        environment: const {'WSL_UTF8': '1'},
      ).timeout(const Duration(seconds: 30));
      final dirs = (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toSet();
      return StackDetection(installedDirs: dirs);
    } catch (error) {
      return StackDetection(
        installedDirs: const {},
        error: 'No se pudo consultar WSL2: $error',
      );
    }
  }

  /// Bytes que ocupa hoy `~/models/<dir>` dentro de WSL2, o `null` si no se pudo
  /// medir. Lo usa la barra de progreso de una descarga del stack.
  ///
  /// Es una lectura barata (`du -sb`), y solo se llama mientras hay una
  /// descarga en marcha. `hf download --local-dir` copia los ficheros al
  /// directorio del modelo, asi que su tamano crece de forma monotona.
  Future<int?> modelDirBytes({
    required String distro,
    required String dir,
  }) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'wsl.exe',
        ['-d', distro, '-e', 'bash', '-lc', 'du -sb ~/models/$dir 2>/dev/null'],
        environment: const {'WSL_UTF8': '1'},
      ).timeout(const Duration(seconds: 15));
      final fields = (result.stdout as String).trim().split(RegExp(r'\s+'));
      if (fields.isEmpty) return null;
      return int.tryParse(fields.first);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _distroRunning(String distro) async {
    final result = await Process.run(
      'wsl.exe',
      ['-l', '-v'],
      environment: const {'WSL_UTF8': '1'},
    ).timeout(const Duration(seconds: 15));
    final text = result.stdout as String;
    for (final line in text.split('\n')) {
      final clean = line.replaceAll('*', ' ').trim();
      if (clean.isEmpty) continue;
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts.first == distro) {
        return parts[1].toLowerCase().startsWith('running');
      }
    }
    return false;
  }
}
