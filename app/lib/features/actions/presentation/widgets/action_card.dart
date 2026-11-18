import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../domain/deck_action.dart';
import 'action_icons.dart';

class ActionCard extends StatefulWidget {
  const ActionCard({
    super.key,
    required this.action,
    required this.onExecute,
    required this.onEdit,
    required this.onDelete,
    this.promptParamCount = 0,
    this.entryDelay = Duration.zero,
  });

  final DeckAction action;
  final VoidCallback onExecute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Cuantos datos se le van a pedir al usuario al tocar la tarjeta.
  ///
  /// Lo calcula la grilla con `promptParametersFor` y no la tarjeta, porque
  /// para una macro son los parametros de sus PASOS: hace falta la lista
  /// completa de acciones para resolverlos, y la tarjeta solo conoce la
  /// suya. Es el mismo numero que ve el telefono (la PC se lo manda ya
  /// resuelto en el catalogo).
  final int promptParamCount;

  /// Retraso antes de que la tarjeta entre en escena (animacion
  /// escalonada de la grilla al abrir la pantalla).
  final Duration entryDelay;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  /// El menu se atenua en reposo, pero **nunca se oculta del todo**: hay
  /// laptops Windows con pantalla tactil, donde no hay hover y un menu a
  /// opacidad 0 seria inalcanzable.
  static const _menuIdleOpacity = 0.35;

  bool _hovered = false;

  void _onMenuSelected(_ActionCardMenu? value) => switch (value) {
    _ActionCardMenu.edit => widget.onEdit(),
    _ActionCardMenu.delete => widget.onDelete(),
    null => null,
  };

  /// Menu contextual en la posicion del clic derecho. Se arma con
  /// `showMenu` y no reusando el `PopupMenuButton` porque para eso habria
  /// que llamarle un metodo de estado por reflexion.
  Future<void> _showContextMenu(TapUpDetails details) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      details.globalPosition & Size.zero,
      Offset.zero & overlay.size,
    );
    _onMenuSelected(
      await showMenu<_ActionCardMenu>(
        context: context,
        position: position,
        items: _menuItems,
      ),
    );
  }

  /// Lo que hay que saber ANTES de tocar la tarjeta: que va a pedir el UAC,
  /// que va a abrir un dialogo pidiendo datos, o que va a correr varios
  /// pasos y tardar. Las tres cosas cambian que pasa al hacer clic.
  List<Widget> get _badges {
    final action = widget.action;
    final steps = action.macroSteps.length;
    return [
      if (action.requiresAdmin)
        const _MetaBadge(icon: Icons.admin_panel_settings, label: 'Admin'),
      if (action.actionType == ActionType.macro)
        _MetaBadge(
          icon: Icons.playlist_play_rounded,
          label: steps == 1 ? '1 paso' : '$steps pasos',
        ),
      if (widget.promptParamCount > 0)
        _MetaBadge(
          icon: Icons.tune_rounded,
          label: widget.promptParamCount == 1
              ? '1 dato'
              : '${widget.promptParamCount} datos',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(widget.action.colorHex);
    final theme = Theme.of(context);
    final description = widget.action.description;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InteractiveCard(
        accent: color,
        onTap: widget.onExecute,
        // Click derecho = menu contextual, convencion de escritorio.
        onSecondaryTapUp: _showContextMenu,
        semanticLabel: widget.action.name,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Wash de esquina en lugar de la franja de 3 px de arriba: la
            // franja lee "tarjeta de Material 2015", el degradado tine la
            // tarjeta entera con el color de la accion sin gritar.
            AnimatedContainer(
              duration: AppDuration.hover,
              curve: AppCurves.emphasized,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.center,
                  colors: [
                    color.withValues(alpha: _hovered ? 0.16 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Padding(
              // 12 y no 8: en escritorio la tarjeta mide ~350x205 px y 8 px
              // de padding la hacen ver apretada, de movil.
              padding: const EdgeInsets.all(AppSpacing.md),
              // `LayoutBuilder` + `FittedBox(scaleDown)` alrededor de TODO
              // el contenido: es lo que garantiza que la tarjeta NUNCA
              // desborda, sin importar que tan chica termine la celda que le
              // da la grilla -- encontrado en vivo dos veces (el riel de
              // metricas bien ancho con el deck a 2 columnas, y despues 20+
              // acciones forzando muchas filas en una ventana baja: ahi ni
              // siquiera el icono+nombre entraban, y un fix que solo protegia
              // la descripcion no alcanzaba). `FittedBox` mide a su hijo SIN
              // acotar, asi que un `Spacer()` adentro (el de la fila del
              // icono) revienta sin ancho conocido -- por eso el
              // `LayoutBuilder` de afuera le fija a la `Column` el ancho real
              // de la celda con un `SizedBox`, y solo el ALTO queda libre
              // para que `FittedBox` decida si hace falta achicar.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _IconChip(color: color, icon: widget.action.icon),
                              const Spacer(),
                              AnimatedOpacity(
                                opacity: _hovered ? 1 : _menuIdleOpacity,
                                duration: AppDuration.hover,
                                curve: AppCurves.emphasized,
                                child: PopupMenuButton<_ActionCardMenu>(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Opciones',
                                  onSelected: _onMenuSelected,
                                  itemBuilder: (context) => _menuItems,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            widget.action.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Tooltip(
                              // La descripcion se elipsa: el tooltip es la
                              // unica forma de leerla completa sin abrir el
                              // editor.
                              message: description,
                              child: Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          if (_badges.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            // `Wrap` y no `Row`: en el deck de una ventana
                            // angosta las tarjetas se achican y tres
                            // insignias en una linea desbordan.
                            Wrap(
                              spacing: AppSpacing.md,
                              runSpacing: AppSpacing.xxs,
                              children: _badges,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: widget.entryDelay).fadeIn(duration: AppDuration.entry).scale(
      begin: const Offset(0.92, 0.92),
      end: const Offset(1, 1),
      duration: AppDuration.entry,
      curve: AppCurves.standard,
    );
  }
}

/// Cuadro del icono. El degradado + el borde del mismo color le dan
/// volumen sin sombras: un relleno plano al 15% se veia lavado.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.color, required this.icon});

  final Color color;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(iconForName(icon), size: 18, color: color),
    );
  }
}

/// Insignia discreta al pie de la tarjeta (icono + palabra). Generaliza la
/// que existia solo para "Admin": el lenguaje visual ya estaba resuelto y
/// no hay razon para que "3 pasos" se vea distinto.
class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          // Cifras tabulares: el conteo de pasos cambia al editar la macro
          // y no tiene por que mover el ancho de la insignia.
          style: AppText.numeric(
            theme.textTheme.labelSmall,
          )?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

enum _ActionCardMenu { edit, delete }

/// Los items del menu, compartidos por el boton "..." y por el click
/// derecho, para que las dos entradas no puedan divergir.
const _menuItems = <PopupMenuEntry<_ActionCardMenu>>[
  PopupMenuItem(value: _ActionCardMenu.edit, child: Text('Editar')),
  PopupMenuItem(value: _ActionCardMenu.delete, child: Text('Eliminar')),
];
