import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado del stack segun la pasarela (`GET /health`, sin clave).
///
/// `reachable` es false cuando la pasarela no contesta: eso distingue «no hay
/// nada levantado» de «no llego a la pasarela» (apagada, o el stack a medias).
class StackHealth {
  const StackHealth({
    required this.reachable,
    this.router,
    this.fast,
    this.complex,
    this.writer,
  });

  const StackHealth.unreachable() : this(reachable: false);

  final bool reachable;
  final String? router;
  final String? fast;
  final String? complex;
  final String? writer;

  bool get hasAnythingUp =>
      _up(router) || _up(fast) || _up(complex) || _up(writer);

  /// El estado de un rol del stack por su nombre de `models.json`, para no
  /// repetir el mapeo rol→campo en cada lugar que mira la salud.
  bool isUp(String role) => switch (role) {
    'router' => _up(router),
    'fast' => _up(fast),
    'complex' => _up(complex),
    'writer' => _up(writer),
    _ => false,
  };

  static bool _up(String? state) => state == 'up';
}

/// Si **todos** los [roles] del stack estan `up`. Un perfil esta "iniciado"
/// cuando lo estan los suyos; `reachable` tiene que ser true y la lista no puede
/// estar vacia (un perfil sin roles locales, o con la pasarela caida, no lo
/// esta). Pura y testeada.
bool stackRolesStarted(Set<String> roles, StackHealth health) =>
    roles.isNotEmpty && health.reachable && roles.every(health.isUp);

/// Sondea la pasarela mientras alguien mire el resultado (el switch), cada
/// pocos segundos. `autoDispose`: con el panel cerrado no queda ningun timer.
///
/// Se usa `dart:io` a proposito: es una funcion de escritorio que habla con
/// loopback, y no vale la pena sumar una dependencia HTTP por esto.
final stackHealthProvider = StreamProvider.autoDispose<StackHealth>((ref) {
  return _healthLoop();
});

Stream<StackHealth> _healthLoop() async* {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    while (true) {
      yield await _fetch(client);
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  } finally {
    client.close(force: true);
  }
}

Future<StackHealth> _fetch(HttpClient client) async {
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:8888/health'),
    );
    final response = await request.close();
    if (response.statusCode != 200) return const StackHealth.unreachable();
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const StackHealth.unreachable();
    final backends = decoded['backends'];
    final map = backends is Map ? backends : const {};
    return StackHealth(
      reachable: true,
      router: map['router']?.toString(),
      fast: map['fast']?.toString(),
      complex: map['complex']?.toString(),
      writer: map['writer']?.toString(),
    );
  } catch (_) {
    // Pasarela caida, a medio arrancar, o el puerto ocupado por otra cosa.
    return const StackHealth.unreachable();
  }
}
