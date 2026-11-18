import 'package:nexodeck/src/rust/api/components.dart' as bridge;

/// Nombres y caracteristicas de las piezas del equipo, para poner un modelo
/// concreto al lado de cada metrica ("CPU" contra "Ryzen 7 5700X").
///
/// Se lee **una vez** por sesion: nada de esto cambia mientras la app corre.
/// Mismo criterio de separacion que `HardwareSnapshot`: el tipo del bridge no
/// llega a los widgets.
class HostComponents {
  const HostComponents({
    this.cpuName,
    this.ramVendor,
    this.ramPartNumber,
    this.ramSpeedMts,
    this.ramSpeedRatedMts,
    this.ramModuleCount,
    this.gpuName,
    this.gpuVramTotalMb,
    this.networkAdapter,
  });

  factory HostComponents.fromBridge(bridge.HostComponents c) => HostComponents(
    cpuName: c.cpuName,
    ramVendor: c.ramVendor,
    ramPartNumber: c.ramPartNumber,
    ramSpeedMts: c.ramSpeedMts,
    ramSpeedRatedMts: c.ramSpeedRatedMts,
    ramModuleCount: c.ramModuleCount,
    gpuName: c.gpuName,
    gpuVramTotalMb: c.gpuVramTotalMb,
    networkAdapter: c.networkAdapter,
  );

  /// Vacio: lo que ve el telefono, que recibe metricas por red pero no las
  /// piezas de la PC. Con todo en `null` las tiles no dibujan subtitulo y
  /// quedan exactamente como estaban.
  static const empty = HostComponents();

  final String? cpuName;
  final String? ramVendor;
  final String? ramPartNumber;
  final int? ramSpeedMts;
  final int? ramSpeedRatedMts;
  final int? ramModuleCount;
  final String? gpuName;
  final double? gpuVramTotalMb;
  final String? networkAdapter;

  /// El subtitulo de la tile de CPU. Los procesadores traen coletillas que no
  /// aportan y comen el ancho (`8-Core Processor`, `CPU @ 3.40GHz`), asi que
  /// se recortan: el modelo es lo que identifica la pieza.
  String? get cpuLabel => _shortenCpu(cpuName);

  /// `Corsair · 3600 MT/s`: **la marca y la velocidad primero**.
  ///
  /// El numero de parte es lo que se sacrifica. Los reales son largos
  /// (`CM4X16GD3600C18K2D`) y se comian la linea entera dejando la velocidad
  /// en "· 360…" -- verificado en la app. Se usa solo cuando no hay marca, y
  /// ahi va recortado: sirve para reconocer el modulo, no para leerlo entero.
  String? get ramLabel {
    final parts = <String>[
      if (_ramName != null) _ramName!,
      if (ramSpeedLabel != null) ramSpeedLabel!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// La memoria esta corriendo por debajo de lo que declara su etiqueta:
  /// tipicamente, el perfil XMP/DOCP no esta activo en la BIOS. Es el dato que
  /// convierte "3600 MT/s" de un numero en una respuesta: **esta corriendo a
  /// eso, o solo lo promete**.
  bool get ramBelowRatedSpeed {
    final actual = ramSpeedMts;
    final rated = ramSpeedRatedMts;
    if (actual == null || rated == null) return false;
    return actual < rated;
  }

  /// `3600 MT/s`, o `2133 de 3600 MT/s` cuando no llega a lo prometido.
  String? get ramSpeedLabel {
    final actual = ramSpeedMts;
    if (actual == null) return null;
    return ramBelowRatedSpeed
        ? '$actual de $ramSpeedRatedMts MT/s'
        : '$actual MT/s';
  }

  /// Cuantos modulos hay, para el badge. Solo si son varios: "1 módulo" no le
  /// dice nada a nadie.
  String? get ramModulesLabel =>
      (ramModuleCount ?? 0) > 1 ? '$ramModuleCount módulos' : null;

  String? get _ramName {
    final vendor = ramVendor?.trim();
    if (vendor != null && vendor.isNotEmpty) return vendor;

    final part = ramPartNumber?.trim();
    if (part == null || part.isEmpty) return null;
    // El numero de parte suele traer la marca codificada al principio
    // ("CM..." de Corsair, "KHX..." de Kingston), asi que recortar por el
    // final conserva la parte que identifica.
    return part.length <= _kMaxPartNumber
        ? part
        : '${part.substring(0, _kMaxPartNumber)}…';
  }

  /// Lo que entra en el riel sin desplazar a la velocidad.
  static const _kMaxPartNumber = 10;

  /// `RTX 5060 Ti · 16 GB`.
  ///
  /// El reloj **no** va aca aunque sea una caracteristica de la pieza: cambia
  /// con la carga, asi que viaja en el snapshot y se dibuja como badge junto a
  /// la temperatura, donde se lo ve moverse.
  String? get gpuLabel {
    final parts = <String>[
      if (gpuName != null) _shortenGpu(gpuName!),
      if (gpuVramTotalMb != null) _vramLabel(gpuVramTotalMb!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get networkLabel => networkAdapter;

  /// VRAM redondeada a giga entero: `15.9 GB` es ruido cuando lo que se quiere
  /// decir es que la tarjeta tiene 16.
  static String _vramLabel(double mb) => '${(mb / 1024).round()} GB';

  static String? _shortenCpu(String? name) {
    if (name == null) return null;
    var short = name;
    for (final noise in [
      RegExp(r'\s*\d+-Core Processor', caseSensitive: false),
      RegExp(r'\s*\bCPU\b'),
      RegExp(r'\s*@.*$'),
      RegExp(r'\s*\((R|TM|r|tm)\)'),
    ]) {
      short = short.replaceAll(noise, '');
    }
    short = short.replaceAll(RegExp(r'\s+'), ' ').trim();
    return short.isEmpty ? name : short;
  }

  /// `NVIDIA GeForce RTX 5060 Ti` -> `GeForce RTX 5060 Ti`. El fabricante ya
  /// se sabe por el contexto y son diez caracteres que no entran.
  static String _shortenGpu(String name) {
    final short = name
        .replaceAll(RegExp(r'^\s*(NVIDIA|AMD|Intel)\s+', caseSensitive: false), '')
        .trim();
    return short.isEmpty ? name : short;
  }
}
