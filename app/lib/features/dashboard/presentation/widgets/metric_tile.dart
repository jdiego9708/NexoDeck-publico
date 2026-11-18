import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../domain/metric_badge.dart' show MetricBadge, MetricBadgePosition;
import 'metric_specs.dart';

/// Cuanta informacion entra en la tile. Lo decide el layout (`MetricsPanel`)
/// midiendo el espacio real, no la plataforma: una tablet en horizontal y
/// una ventana de escritorio angosta pueden terminar en la misma densidad.
enum MetricDensity {
  /// Chart grande + titulo + valor + badges. Franja ancha con altura de sobra.
  full,

  /// Mismo contenido que [full] pero mas apretado (chart chico, tipografia
  /// menor). Es el modo del riel vertical y de la franja en telefono.
  compact,

  /// Solo chart + valor. Ultimo recurso cuando no entra ni el titulo.
  micro,
}

/// Contenedor comun para cada metrica: chart a la izquierda,
/// titulo/valor/badges a la derecha (o apilados en [MetricDensity.micro]).
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.spec,
    this.density = MetricDensity.full,
    this.expanded = false,
    this.entryDelay = Duration.zero,
    this.onTap,
    this.selected = false,
  });

  final MetricSpec spec;
  final MetricDensity density;

  /// Si la tile consiguio el ancho extra que pidio (`MetricSpec.widthUnits`)
  /// y tiene que dibujar `MetricSpec.expandedBuilder` en vez del chart. Lo
  /// decide `MetricsPanel`, que es el unico que sabe cuanto espacio hay.
  final bool expanded;

  /// Retraso antes de que la tile entre en escena (animacion escalonada de
  /// las 5 metricas al abrir la pantalla).
  final Duration entryDelay;

  /// Abre el desglose de procesos de esta metrica. En `null` la tile no es
  /// clicable en absoluto --ni cursor, ni foco de teclado, ni `Semantics` de
  /// boton--, que es como quedan las metricas sin desglose (Disco y Red), el
  /// espejo del telefono y la ventana compacta.
  final VoidCallback? onTap;

  /// El desglose de esta metrica es el que se esta viendo.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `InteractiveCard` y no `Card`: es la unica fuente de verdad del borde
    // de una superficie clickeable (hover, foco de teclado con Enter/Espacio,
    // presionado). Envolver una en la otra dibujaria dos bordes -- ver
    // CLAUDE.md. Con `onTap: null` se comporta como una tarjeta inerte, que
    // es lo que era antes.
    return InteractiveCard(
      onTap: onTap,
      selected: selected,
      accent: spec.accentColor,
      semanticLabel: onTap == null
          ? null
          : 'Ver procesos que mas usan ${spec.title}',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: density == MetricDensity.full
              ? AppSpacing.md
              : AppSpacing.sm,
          vertical: density == MetricDensity.micro ? 4 : AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => switch (density) {
            MetricDensity.micro => _buildMicro(theme),
            _ when expanded && spec.expandedBuilder != null => _buildExpanded(
              context,
              theme,
            ),
            _ => _buildRow(theme, constraints),
          },
        ),
      ),
    ).animate(delay: entryDelay).fadeIn(duration: AppDuration.entrySlow).slideY(
      begin: 0.15,
      end: 0,
      duration: AppDuration.entrySlow,
      curve: AppCurves.standard,
    );
  }

  Widget _buildMicro(ThemeData theme) {
    // `scaleDown` y no `ellipsis`: en la franja del modo compacto la tile
    // mide ~52 dp de ancho y valores como `1747.1 GB` o `↓19.5 KB/s` no
    // entran a tamano completo. Cortarlos con puntos suspensivos dejaria el
    // numero sin sus unidades, que es exactamente la parte que hace falta
    // leer.
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      child: _valueText(theme, theme.textTheme.labelMedium),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Con ancho de sobra, apilar deja el chart aplastado contra el alto
        // de la franja: el donut de RAM/GPU se dibujaba tan chico que su
        // porcentaje interior no se leia. Ver `microMetricRowMinWidth`.
        if (constraints.maxWidth >= AppSizes.microMetricRowMinWidth) {
          return Row(
            children: [
              Expanded(child: spec.chart),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: value),
            ],
          );
        }
        // Sin caja fija para el chart: toma la altura que sobre despues del
        // valor, para que la tile funcione igual a 48 o a 80 px de alto.
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: spec.chart),
            const SizedBox(height: AppSpacing.xxs),
            value,
          ],
        );
      },
    );
  }

  /// Cabecera (titulo + valor + badges en una linea) y debajo el cuerpo que
  /// aporta la metrica. Reemplaza al chart, no lo acompana: la lista de
  /// discos ya ES el grafico, y dejar los dos obligaria a partir el ancho
  /// justo cuando se lo dio para mostrar mas detalle.
  Widget _buildExpanded(BuildContext context, ThemeData theme) {
    final titleStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return _expandedBody(context, theme, titleStyle);
  }

  Widget _expandedBody(
    BuildContext context,
    ThemeData theme,
    TextStyle? titleStyle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El titulo se queda con la fila entera, asi que siempre entra el
        // largo ("Almacenamiento" y no "Disco"): el agregado se movio abajo
        // justamente para no competir con el.
        Text(
          spec.expandedTitle ?? spec.title,
          style: titleStyle,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(child: spec.expandedBuilder!(context)),
        const SizedBox(height: AppSpacing.xs),
        // El total, al pie: es el resumen de lo que esta arriba, y leerlo
        // despues de las filas es el orden en que uno lo mira.
        _valueAndBadgesRow(theme, theme.textTheme.titleSmall, spec.badges),
      ],
    );
  }

  Widget _buildRow(ThemeData theme, BoxConstraints constraints) {
    final availableHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : AppSizes.minStackedTileHeight;
    final isFull = density == MetricDensity.full;
    final titleStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    // El grafico a lo ancho pide DOS cosas, y las dos se miden: densidad
    // completa y alto suficiente para las filas. La franja de un telefono da
    // tiles que son `full` pero de ~100 dp, y ahi el apilado desbordaba.
    if (spec.stackedChart &&
        isFull &&
        availableHeight >= AppSizes.minStackedTileHeight) {
      return _buildStackedChart(
        theme,
        titleStyle,
        constraints.maxWidth,
        availableHeight,
      );
    }

    final subtitle = _subtitleText(theme, availableHeight);

    // Lo que arriba dibujan el grafico o la barra de capacidad (la
    // temperatura y la frecuencia del CPU, la VRAM de la GPU) aca vuelve a ser
    // un badge: en el reparto lateral el grafico no tiene ancho para
    // mostrarlo, y perderlo es justo lo que el riel viene evitando.
    final badges = [...spec.badges, ...spec.fallbackBadges];

    return Row(
      children: [
        SizedBox(
          width: isFull ? 48 : 36,
          height: double.infinity,
          child: spec.chart,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Compacto pone titulo y valor en la MISMA linea: ahorra ~14
              // dp por tile, que es lo que hace que las 5 entren en el riel
              // de un telefono apaisado sin scrollear.
              if (isFull) ...[
                Text(spec.title, style: titleStyle, overflow: TextOverflow.ellipsis),
                if (subtitle != null) subtitle,
                _valueText(theme, theme.textTheme.titleMedium),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      spec.title,
                      style: titleStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _valueText(theme, theme.textTheme.titleSmall),
                    ),
                  ],
                ),
              if (badges.isNotEmpty)
                // Una sola linea que se achica si hace falta, en vez de un
                // `Wrap`: envolviendo a dos lineas los badges no entraban en
                // el alto de la tile y el segundo (la VRAM de la GPU)
                // quedaba cortado por la mitad en el telefono.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final badge in badges) ...[
                        _badgeWidget(theme, badge),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sin `AnimatedSwitcher`: el valor cambia una vez por segundo y el
  /// crossfade de 300 ms superponia el numero viejo con el nuevo, asi que
  /// casi un tercio del tiempo se veia doble/borroso. La animacion que
  /// queda es la de entrada de la tile.
  /// Titulo arriba, grafico a lo ancho en el medio, y valor con badges
  /// abajo. Lo usa la RAM: sus dos modulos necesitan ancho para leerse como
  /// modulos y no como dos rayas.
  Widget _buildStackedChart(
    ThemeData theme,
    TextStyle? titleStyle,
    double availableWidth,
    double availableHeight,
  ) {
    final subtitle = _subtitleText(theme, availableHeight);
    // El grafico dibuja lo que dice `fallbackBadges` **solo si tiene ancho**:
    // la tile de CPU reparte su caja entre las cifras, el chip y el
    // termometro, y en una franja de escritorio angosta esas tres columnas no
    // entran. Ahi la temperatura y la frecuencia vuelven abajo, en vez de
    // desaparecer.
    final badges = [
      ...spec.badges,
      if (availableWidth < spec.chartMinWidth) ...spec.fallbackBadges,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titulo a la izquierda y, enfrentado, el dato que describe al
        // componente: arriba no compite con las cifras que se mueven.
        Row(
          children: [
            // `Expanded` y no `Flexible`: el titulo se queda con el ancho que
            // sobra y empuja el badge contra el borde. Con `Flexible` los dos
            // se encogen a su contenido y el badge queda pegado al titulo, que
            // es lo contrario de enfrentarlos.
            Expanded(
              child: Text(
                spec.title,
                style: titleStyle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (spec.headerBadge != null) ...[
              const SizedBox(width: AppSpacing.xs),
              _InfoBadge(
                text: spec.headerBadge!,
                color: spec.accentColor,
                subtle: true,
              ),
            ],
          ],
        ),
        if (subtitle != null) subtitle,
        const SizedBox(height: AppSpacing.sm),
        // El grafico se queda con lo que sobre despues del texto, que es lo
        // que hace que la tile funcione igual a 86 o a 160 dp de alto. Con
        // subtitulo sobra menos, y ese es justamente el efecto buscado: los
        // modulos se achican para que el modelo de la memoria tenga lugar.
        // El grafico se queda con el alto que sobra, pero **no con todo**:
        // `_kStackedChartHeightFactor` le deja aire arriba y abajo. Sin eso,
        // la placa de la GPU y los modulos de la RAM crecian hasta empujar el
        // valor y los badges contra el borde de la tile.
        Expanded(
          child: Center(
            child: FractionallySizedBox(
              heightFactor: _kStackedChartHeightFactor,
              // Cuadrado para la Red: sus dos curvas se leen como una forma, y
              // estiradas a lo ancho se aplastan hasta parecer dos rayas.
              child: spec.squareChart
                  ? AspectRatio(aspectRatio: 1, child: spec.chart)
                  : spec.chart,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _stackedValues(theme, badges),
        if (spec.bottomBar != null) ...[
          const SizedBox(height: AppSpacing.xs),
          spec.bottomBar!,
        ],
      ],
    );
  }

  /// El valor (o su badge, ver `MetricSpec.valueAsBadge`) seguido de sus
  /// badges `inline`, un badge `center` a mitad de camino del resto de la
  /// fila, y los badges `end` anclados al borde derecho -- pedido explicito
  /// para el porcentaje de RAM/Disco y el reloj de GPU. Comparten esta
  /// definicion `_expandedBody` (el pie de la lista de discos) y
  /// `_stackedValues` (RAM/GPU): son la misma pregunta ("valor + badges, en
  /// una fila") con dos titulos de tipografia distintos.
  ///
  /// El bloque valor+`inline` va dentro de un `Flexible(FittedBox(...))`
  /// -- se achica antes que desbordar, igual que antes -- y NO dentro del
  /// mismo `Row` que el `Expanded` del badge `center`: un `Expanded`
  /// necesita ancho acotado desde su padre inmediato, y un `FittedBox` se
  /// lo da sin acotar a props hijos que lo requieran.
  Widget _valueAndBadgesRow(
    ThemeData theme,
    TextStyle? valueStyle,
    List<MetricBadge> badges,
  ) {
    final inlineBadges = badges
        .where((b) => b.position == MetricBadgePosition.inline)
        .toList();
    final centerBadges = badges
        .where((b) => b.position == MetricBadgePosition.center)
        .toList();
    final endBadges = badges
        .where((b) => b.position == MetricBadgePosition.end)
        .toList();

    final value = spec.valueAsBadge
        ? _InfoBadge(
            text: spec.valueText,
            color: spec.valueColor ?? spec.accentColor,
            big: true,
          )
        : _valueText(theme, valueStyle, colorOverride: spec.valueColor);

    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                value,
                for (final badge in inlineBadges) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _badgeWidget(theme, badge),
                ],
              ],
            ),
          ),
        ),
        if (centerBadges.isNotEmpty || endBadges.isNotEmpty)
          Expanded(
            child: centerBadges.isEmpty
                ? const SizedBox.shrink()
                // `FittedBox(scaleDown)`, mismo motivo que el resto de esta
                // fila: `Expanded` le da un tercio parejo del ancho (los tres
                // hijos son flex:1), y en el riel ese tercio puede quedar por
                // debajo de lo que el badge de temperatura necesita a tamano
                // completo -- sin esto desbordaba de costado.
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // El separador va ENTRE badges, no antes de cada uno
                        // como en los `end`: aca el bloque esta centrado en el
                        // hueco, y un espacio a la izquierda del primero lo
                        // correria de su centro.
                        for (final (index, badge) in centerBadges.indexed) ...[
                          if (index > 0) const SizedBox(width: AppSpacing.xs),
                          _badgeWidget(theme, badge),
                        ],
                      ],
                    ),
                  ),
          ),
        // `Flexible` + `FittedBox(scaleDown)`, igual que el valor de arriba:
        // en el riel la tile de GPU mide ~140-180 dp, y los badges de
        // temperatura + velocidad como hijos fijos del Row no podian
        // encogerse -- desbordaban de costado apenas el riel se apretaba.
        if (endBadges.isNotEmpty)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final badge in endBadges) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _badgeWidget(theme, badge),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// El valor con sus badges: en una linea, o uno debajo del otro cuando la
  /// metrica tiene dos cifras del mismo peso (la Red: bajada y subida).
  ///
  /// En los dos casos van dentro de un `FittedBox`: en el riel la tile mide
  /// ~190 dp de ancho y `23.8 GB` con dos badges no entra a tamano completo.
  Widget _stackedValues(ThemeData theme, List<MetricBadge> badges) {
    if (!spec.stackedValues) {
      return _valueAndBadgesRow(theme, theme.textTheme.titleMedium, badges);
    }

    // Enfrentadas en la misma linea: bajada a la izquierda, subida a la
    // derecha. Son dos cifras del mismo peso y en extremos opuestos se
    // comparan de un vistazo, sin que ninguna parezca el subtitulo de la otra.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      // `spaceBetween` y no solo `Flexible`: sin esto las dos cifras se
      // encogen a su contenido y terminan pegadas a la izquierda, que es
      // justo lo contrario de enfrentarlas.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _valueText(
              theme,
              theme.textTheme.titleSmall,
              colorOverride: spec.valueColor,
            ),
          ),
        ),
        for (final badge in badges) ...[
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: spec.badgesAreValues
                  // Sin caja: enfrentada a la bajada, la subida de la Red es
                  // una cifra mas y no un dato al margen. El color por
                  // defecto sigue siendo gris (dato secundario); uno propio
                  // en el badge es la Red cargada avisando.
                  ? Text(
                      badge.text,
                      style: AppText.numeric(
                        theme.textTheme.titleSmall?.copyWith(
                          color:
                              badge.color ?? theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      maxLines: 1,
                    )
                  // Con caja: al lado de un valor grande, el texto plano se
                  // veia suelto, sin nada que lo agrupara.
                  : _badgeWidget(theme, badge),
            ),
          ),
        ],
      ],
    );
  }

  /// Cuanto del alto sobrante toma el grafico en el layout apilado. El resto
  /// es aire: es lo que separa la pieza dibujada de las cifras y hace que la
  /// tile no se vea amontonada.
  static const double _kStackedChartHeightFactor = 0.82;

  /// La pieza concreta ("Ryzen 7 5700X"), chica y atenuada bajo el titulo.
  ///
  /// Devuelve `null` --y entonces no ocupa nada-- cuando no hay dato o cuando
  /// la tile no tiene alto para el: es contexto, y **nunca** puede desplazar
  /// al valor, que es a lo que el usuario vino. En una sola linea con
  /// `ellipsis`, porque los nombres de GPU son largos y arbitrarios.
  Widget? _subtitleText(ThemeData theme, double availableHeight) {
    final subtitle = spec.subtitle;
    if (subtitle == null || density != MetricDensity.full) return null;

    // El subtitulo se come una linea entera, asi que solo entra cuando la
    // tile pasa del minimo de la densidad completa. En la franja de un
    // telefono vertical (que mide justo ese minimo) no entra: mostrarlo
    // empujaba la fila de valores fuera de la tile y Flutter dibujaba la
    // banda de overflow -- le pasaba a RAM y a Red. Ver
    // `minFullMetricTileWithSubtitleHeight`.
    final tileHeight = availableHeight + AppSpacing.sm * 2;
    if (tileHeight < AppSizes.minFullMetricTileWithSubtitleHeight) return null;

    return Text(
      subtitle,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
        fontSize: 10,
        height: 1.1,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _valueText(
    ThemeData theme,
    TextStyle? style, {
    Color? colorOverride,
  }) {
    return Text(
      spec.valueText,
      // Cifras tabulares: sin esto el valor cambia de ancho al pasar de
      // `9%` a `10%` (o de `1` a `8`) y el numero "baila" en su lugar una
      // vez por segundo. No agranda el peor caso, solo lo hace constante.
      style: AppText.numeric(
        style?.copyWith(
          fontWeight: FontWeight.w800,
          color: colorOverride,
        ),
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  /// Un badge ya resuelto: plano (sin caja) o dentro de `_InfoBadge`, con su
  /// color propio si lo tiene o el de la tile si no.
  Widget _badgeWidget(ThemeData theme, MetricBadge badge) {
    if (badge.plain) {
      return Text(
        badge.text,
        style: AppText.numeric(
          theme.textTheme.labelSmall?.copyWith(
            color: badge.color ?? theme.colorScheme.onSurfaceVariant,
          ),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return _InfoBadge(text: badge.text, color: badge.color ?? spec.accentColor);
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.text,
    required this.color,
    this.subtle = false,
    this.big = false,
  });

  final String text;
  final Color color;

  /// Version discreta, para lo que **describe** al componente en vez de
  /// medirlo (cuantos modulos de memoria hay). Es un dato de contexto: tiene
  /// que estar, pero no puede pesar lo mismo que una cifra que se mueve.
  final bool subtle;

  /// Version grande, para cuando el badge ES el valor principal (la RAM en
  /// GB) y no un dato secundario -- mismo tratamiento visual (caja, borde),
  /// tipografia de valor en vez de `labelSmall`.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = subtle ? theme.colorScheme.onSurfaceVariant : color;
    final baseStyle = big
        ? theme.textTheme.titleMedium
        : theme.textTheme.labelSmall;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: subtle ? 4 : (big ? 8 : 6),
        vertical: big ? 2 : 1,
      ),
      decoration: BoxDecoration(
        color: (subtle ? foreground : color).withValues(
          alpha: subtle ? 0.08 : 0.12,
        ),
        borderRadius: BorderRadius.circular(AppRadius.badge),
        // El borde se pinta DENTRO del `BoxDecoration`, no agrega padding:
        // el badge mide exactamente lo mismo que antes, que importa porque
        // estos badges (MHz, °C, VRAM) estan calibrados para entrar en el
        // riel de un telefono apaisado.
        border: Border.all(
          color: foreground.withValues(alpha: subtle ? 0.14 : 0.20),
        ),
      ),
      child: Text(
        text,
        style: AppText.numeric(
          baseStyle?.copyWith(
            color: foreground,
            fontWeight: subtle ? FontWeight.w500 : FontWeight.w800,
            fontSize: subtle ? 9 : null,
          ),
        ),
      ),
    );
  }
}
