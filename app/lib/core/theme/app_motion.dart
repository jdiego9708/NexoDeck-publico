import 'package:flutter/animation.dart';

/// Tokens de movimiento. Antes estos siete numeros vivian sueltos y
/// repetidos a mano en cada widget (`120`, `150`, `200`, `250`, `300`,
/// `350`, `400`), asi que dos animaciones que deberian sentirse iguales
/// terminaban desincronizadas apenas alguien tocaba una.
///
/// Los nombres son **semanticos**, no numericos: lo que importa es "esto es
/// una reaccion al hover" y no "esto dura 140 ms". Los valores son los que
/// ya estaban en uso, para que extraerlos no cambie nada visualmente.
abstract final class AppDuration {
  /// Hundido de una superficie al presionarla.
  static const press = Duration(milliseconds: 120);

  /// Reaccion al hover/foco. Corta a proposito: mas lenta se siente
  /// pegajosa, mas rapida no se llega a leer.
  static const hover = Duration(milliseconds: 140);

  /// Cambio de seleccion (chips, segmented, color elegido).
  static const selection = Duration(milliseconds: 150);

  /// Cambio de estado dentro de un mismo componente (revelar detalle,
  /// alternar contenido).
  static const state = Duration(milliseconds: 200);

  /// Plegado/desplegado de un panel entero.
  static const collapse = Duration(milliseconds: 250);

  /// Entrada de un elemento en escena.
  static const entry = Duration(milliseconds: 300);

  /// Entrada de elementos mas grandes, que necesitan mas recorrido.
  static const entrySlow = Duration(milliseconds: 350);

  /// Redibujado de un chart cuando llega un dato nuevo.
  static const chart = Duration(milliseconds: 400);

  /// Retraso incremental entre elementos de una grilla al entrar.
  static const staggerFast = Duration(milliseconds: 25);

  /// Idem, para listas cortas donde conviene que se note mas.
  static const staggerSlow = Duration(milliseconds: 60);
}

abstract final class AppCurves {
  /// La curva de toda la app. Es la que ya se usaba en todos lados.
  static const standard = Curves.easeOutCubic;

  /// Para el hundido al presionar, que tiene que cortar antes.
  static const press = Curves.easeOut;

  /// "Emphasized decelerate" de Material 3. Reservada para los cambios de
  /// estado interactivos (hover/foco): arranca mas rapido y frena mas
  /// largo que `standard`, y eso es lo que hace que la superficie se sienta
  /// *reaccionando* en vez de simplemente interpolando.
  static const emphasized = Cubic(0.2, 0, 0, 1);
}

abstract final class AppMotion {
  /// Tope de pasos del stagger de una grilla. Sin tope, una grilla con 40
  /// acciones haria esperar un segundo entero a la ultima tarjeta.
  static const int maxStaggerSteps = 16;
}
