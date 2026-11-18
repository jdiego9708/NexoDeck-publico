import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

import '../../../actions/presentation/widgets/action_icons.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/interactive_card.dart';

/// Version simplificada de `ActionCard` para el rol Android: no se puede
/// editar/borrar una accion del PC desde el celular, y `RemoteAction` no
/// trae descripcion ni flag de admin -- solo icono, nombre y color.
///
/// Ya no necesita estado propio: el hundido al presionar lo maneja
/// `InteractiveCard`, igual que en el deck de escritorio.
class RemoteActionCard extends StatelessWidget {
  const RemoteActionCard({
    super.key,
    required this.action,
    required this.onExecute,
    this.entryDelay = Duration.zero,
  });

  final bridge.RemoteAction action;
  final VoidCallback onExecute;
  final Duration entryDelay;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(action.colorHex);
    final theme = Theme.of(context);

    // Mismo lenguaje que `ActionCard` de escritorio: wash de esquina en vez
    // de la franja de 3 px, y chip de icono con degradado y borde. Lo que NO
    // se toca es la geometria (el `LayoutBuilder`, el `clamp` del icono y el
    // padding `sm`): eso es calibracion tactil verificada en un S24 real.
    // El hover de `InteractiveCard` queda inerte en touch, sin costo.
    return InteractiveCard(
      accent: color,
      onTap: onExecute,
      semanticLabel: action.name,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.center,
                colors: [
                  color.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Distintivos en la esquina libre: una macro tarda (corre varios
          // pasos con pausas) y una accion con parametros va a abrir un
          // dialogo antes de ejecutar. Las dos cosas cambian lo que pasa al
          // tocar, asi que se anuncian ANTES del toque. Van en el `Stack`
          // para no tocar la geometria calibrada del icono y el titulo.
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (action.parameters.isNotEmpty)
                  _CornerBadge(icon: Icons.tune_rounded, color: color),
                if (action.kind == bridge.RemoteActionKind.macro) ...[
                  if (action.parameters.isNotEmpty)
                    const SizedBox(width: AppSpacing.xxs),
                  _CornerBadge(
                    icon: Icons.playlist_play_rounded,
                    color: color,
                    label: '${action.stepCount}',
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                    // La grilla reparte el ancho segun la pantalla (ver
                    // `SliverGridDelegateWithMaxCrossAxisExtent` en
                    // `connected_device_screen.dart`), asi que el icono
                    // escala con la tarjeta en vez de quedarse en 36 px
                    // fijos y desbalancearse en las tarjetas chicas.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final box = (constraints.maxWidth * 0.28).clamp(
                        26.0,
                        44.0,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: box,
                            height: box,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withValues(alpha: 0.22),
                                  color.withValues(alpha: 0.10),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(box / 3),
                              border: Border.all(
                                color: color.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Icon(
                              iconForName(action.icon),
                              size: box * 0.5,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              action.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate(delay: entryDelay).fadeIn(duration: AppDuration.entry).scale(
      begin: const Offset(0.92, 0.92),
      end: const Offset(1, 1),
      duration: AppDuration.entry,
      curve: AppCurves.standard,
    );
  }
}

/// Pastilla chica para la esquina de la tarjeta. Deliberadamente discreta:
/// compite con el icono y el nombre, que son lo que el usuario busca.
class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.icon, required this.color, this.label});

  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs + 1,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          if (label != null) ...[
            const SizedBox(width: 1),
            Text(
              label,
              // Cifras tabulares (token del sistema): el contador de pasos
              // cambia de ancho entre 9 y 10 y la pastilla "saltaria" al
              // re-enviarse el catalogo.
              style: AppText.numeric(
                TextStyle(
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
