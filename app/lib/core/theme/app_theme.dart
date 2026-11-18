import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_spacing.dart';
import 'app_surface.dart';

/// Tema global de NexoDeck: superficies tonales planas (sin blur/glass),
/// sombras suaves, radios grandes -- look "enterprise" tipo
/// Linear/Vercel/Stripe. Seed violeta/indigo, Material 3 puro (todo el
/// resto del `ColorScheme` se deriva algoritmicamente del seed, no hay
/// colores hex sueltos fuera de aca).
abstract final class AppTheme {
  static const _seed = Color(0xFF6C5CE7);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final textTheme = _tighten(
      GoogleFonts.plusJakartaSansTextTheme(base.textTheme),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // El `side` de la forma se pinta SOBRE la superficie, no insetea
          // al hijo, asi que esto no mueve la geometria de ninguna tarjeta
          // (importa: `MetricTile` esta calibrada al pixel contra un
          // telefono real). Sin el, en modo claro las tarjetas practicamente
          // no se despegan del fondo.
          side: AppSurface.hairline(scheme),
        ),
      ),
      appBarTheme: AppBarTheme(
        // Transparente para que el `NeuralBackground` siga vivo detras del
        // chrome en vez de cortarse en una banda: el fondo ya pinta
        // `scheme.surface` opaco, asi que el color no cambia.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
        titleSpacing: AppSpacing.gutter,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        hoverElevation: 6,
        focusElevation: 6,
        extendedTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip + 4),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          // Pill de hover coherente con el resto de las superficies, en vez
          // del circulo gris por defecto de Material.
          hoverColor: scheme.onSurface.withValues(alpha: 0.07),
          highlightColor: scheme.onSurface.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
        ),
      ),
      // Una scrollbar fina que engorda al pasar el mouse es una de las
      // senales mas baratas y mas fuertes de "esto es una app de escritorio".
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(AppRadius.badge),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return scheme.onSurfaceVariant.withValues(
            alpha: hovered ? 0.50 : 0.28,
          );
        }),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      // Sin esto los tooltips salen con el fondo negro por defecto de
      // Material, que rompe el tema en las dos luminancias.
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.fromBorderSide(AppSurface.hairline(scheme)),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        selectedColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        // El borde reacciona al estado en vez de no existir: hairline en
        // reposo, tenido de primario al seleccionar o al pasar el mouse.
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(
              color: scheme.primary.withValues(alpha: 0.45),
              width: 1,
            );
          }
          if (states.contains(WidgetState.hovered)) {
            return BorderSide(
              color: scheme.primary.withValues(alpha: 0.25),
              width: 1,
            );
          }
          return AppSurface.hairline(scheme);
        }),
        // El tilde compite con el punto de color del grupo y no aporta: el
        // relleno tonal + el borde tenido ya dicen que esta seleccionado.
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card + 4),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }

  /// Aprieta el tracking de los titulos grandes. Es lo que separa un titulo
  /// "disenado" de uno con los defaults de Material.
  ///
  /// **Solo toca display/headline/titleLarge a proposito.** `labelSmall`,
  /// `labelMedium`, `titleSmall` y `titleMedium` son exactamente los cuatro
  /// estilos que usa `MetricTile`, cuya altura esta calibrada contra un
  /// telefono real -- y ahi no se toca nada, ni `letterSpacing` ni mucho
  /// menos `height`.
  static TextTheme _tighten(TextTheme t) => t.copyWith(
    displayLarge: t.displayLarge?.copyWith(letterSpacing: -1.0),
    displayMedium: t.displayMedium?.copyWith(letterSpacing: -0.8),
    displaySmall: t.displaySmall?.copyWith(letterSpacing: -0.6),
    headlineLarge: t.headlineLarge?.copyWith(letterSpacing: -0.6),
    headlineMedium: t.headlineMedium?.copyWith(letterSpacing: -0.5),
    headlineSmall: t.headlineSmall?.copyWith(letterSpacing: -0.5),
    titleLarge: t.titleLarge?.copyWith(letterSpacing: -0.4),
  );
}
