import 'package:flutter/painting.dart';

abstract final class AppText {
  /// Cifras tabulares: todos los digitos ocupan el ancho del mas ancho.
  ///
  /// Hace falta en cualquier numero que se actualice solo (las metricas
  /// cambian una vez por segundo): con cifras proporcionales, pasar de `9%`
  /// a `10%` o de `1` a `8` mueve el texto de ancho y el valor "baila" en su
  /// lugar. No agranda el peor caso -- el layout ya tenia que soportar el
  /// digito mas ancho --, solo hace que todos los frames midan igual.
  static TextStyle? numeric(TextStyle? base) =>
      base?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Estilo del PIN de emparejamiento: cifras tabulares + tracking POSITIVO.
  ///
  /// El PIN es un numero que dos humanos comparan digito por digito entre dos
  /// pantallas, asi que necesita lo contrario que un titulo: aire entre
  /// digitos, no menos.
  ///
  /// El `letterSpacing` explicito **no es opcional**: los estilos grandes del
  /// tema llevan tracking negativo (`_tighten` en `app_theme.dart`), y
  /// `copyWith(letterSpacing: null)` NO borra el valor heredado -- lo
  /// conserva. La unica forma de revertirlo es pasar un numero positivo.
  static TextStyle? pin(TextStyle? base, {double tracking = 6.0}) =>
      numeric(base)?.copyWith(
        letterSpacing: tracking,
        fontWeight: FontWeight.w700,
        height: 1.0,
      );
}
