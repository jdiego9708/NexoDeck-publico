import 'package:flutter/material.dart';

/// Un badge de metrica ya resuelto para pintar.
///
/// Antes `MetricSpec.badges` era `List<String>` y todos los badges de una
/// tile compartian el mismo color (`MetricSpec.accentColor`). Los colores
/// por umbral necesitan que un badge puntual (la temperatura, el reloj de la
/// GPU) se pinte distinto del resto sin cambiar el color de toda la tile, y
/// que otro (el "de 31.9 GB" de la RAM) deje de llevar caja. Este tipo carga
/// esas dos decisiones junto con el texto.
class MetricBadge {
  const MetricBadge(
    this.text, {
    this.color,
    this.plain = false,
    this.position = MetricBadgePosition.inline,
  });

  final String text;

  /// `null` = usa `MetricSpec.accentColor`, el color de siempre. Un valor
  /// explicito es lo que permite que ESTE badge puntual se pinte de alerta
  /// mientras el resto de la tile sigue con su color normal.
  final Color? color;

  /// Sin caja ni relleno: texto plano, mismo tratamiento que el titulo. Lo
  /// pide la RAM para "de 31.9 GB", que dejo de ser un dato secundario y
  /// paso a acompanar al valor (que ahora SI lleva caja, ver
  /// `MetricSpec.valueAsBadge`).
  final bool plain;

  /// Donde cae este badge en la fila de valor+badges. Solo lo interpreta
  /// `MetricTile._valueAndBadgesRow` -- el resto de los lugares que dibujan
  /// badges (la fila compacta de `_buildRow`) lo ignoran y los pintan todos
  /// pegados, como siempre.
  final MetricBadgePosition position;
}

/// Donde ancla un badge dentro de la fila de valor+badges.
enum MetricBadgePosition {
  /// Pegado al valor, del lado izquierdo -- el tratamiento de siempre.
  inline,

  /// Centrado en el espacio que sobra entre el bloque de la izquierda
  /// (valor + badges `inline`) y los badges `end`. Lo pide la GPU: la
  /// temperatura va "a mitad de camino" entre el porcentaje y el reloj.
  center,

  /// Anclado al borde derecho de la fila -- pedido explicito para el
  /// porcentaje de RAM/Disco y el reloj de GPU.
  end,
}
