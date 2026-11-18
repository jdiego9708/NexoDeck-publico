import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Boton de acceso al asistente de IA.
///
/// No es un `FloatingActionButton` de verdad: ya hubo uno ahi y se saco
/// porque flotaba SOBRE el deck y tapaba la descripcion de la ultima
/// tarjeta (documentado en `main.dart`, con captura de por medio). Este
/// vive anclado en la barra (misma zona fija que el resto de las
/// acciones, fuera del area scrolleable) pero se ve elevado de verdad —
/// circulo con el degrade de marca (el mismo violeta-magenta del icono de
/// la app) y sombra propia — para que se lea como LA accion destacada sin
/// arriesgar el problema que ya se resolvio una vez.
///
/// El icono combina un bot minimalista con el rayo que ya identifica a
/// NexoDeck (el mismo `Icons.bolt` de `NexoDeckWordmark`), como una
/// insignia chica en la esquina — no un mascota nueva que compita con la
/// marca existente.
class AiAssistantButton extends StatelessWidget {
  const AiAssistantButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Tooltip(
        message: 'Crear con IA',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Ink(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.38),
                    blurRadius: 14,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.smart_toy_rounded, size: 20, color: scheme.onPrimary),
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: scheme.onPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bolt, size: 9, color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
