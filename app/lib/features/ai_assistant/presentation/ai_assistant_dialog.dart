import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/ai_providers.dart';
import '../application/chat_destinations_controller.dart';
import 'conversations_sheet.dart';
import '../domain/chat_backend.dart';
import '../domain/chat_destination.dart';
import 'ai_chat_view.dart';
import 'ai_setup_wizard.dart';

/// Abre el asistente de IA.
///
/// Misma forma que `showHistoryDialog`: un `Dialog` con tamano fijo, que es la
/// convencion del proyecto para una "pantalla dentro de un dialogo" (no hay
/// router; todo se abre con un `showXxx(context)`).
///
/// Marca `aiAssistantDialogOpenProvider` mientras esta abierto -- es lo que
/// deja que `askAiInChat` sepa si tiene que abrir uno nuevo o si ya hay uno
/// escuchando `aiPendingPromptProvider`.
Future<void> showAiAssistantDialog(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(aiAssistantDialogOpenProvider.notifier).state = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => const Dialog(
        insetPadding: EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(width: 900, height: 620, child: AiAssistantPanel()),
      ),
    );
  } finally {
    container.read(aiAssistantDialogOpenProvider.notifier).state = false;
  }
}

/// Mete `prompt` en el chat de IA y lo manda, como si el usuario lo hubiera
/// escrito -- lo usa el boton nuevo de "preguntarle a la IA" del panel de
/// procesos. Si el dialogo ya esta abierto, `AiChatView` esta escuchando
/// `aiPendingPromptProvider` y lo toma solo sin que haga falta abrir nada de
/// nuevo; si no, `showAiAssistantDialog` lo abre y, apenas el chat este
/// listo, `AiChatView.initState` encuentra el pedido pendiente y lo manda.
Future<void> askAiInChat(
  BuildContext context,
  WidgetRef ref,
  String prompt,
) async {
  ref.read(aiPendingPromptProvider.notifier).state = (
    nonce: DateTime.now().microsecondsSinceEpoch,
    text: prompt,
  );
  if (!ref.read(aiAssistantDialogOpenProvider)) {
    await showAiAssistantDialog(context);
  }
}

/// El cuerpo del asistente: cabecera + (wizard o chat).
///
/// Es **el mismo widget** en las dos partes: el dialogo de siempre (boton de la
/// barra, atajo del panel de procesos) y el centro de la pantalla principal
/// (`HomeLayout.controlCenter`). No hay una segunda implementacion del chat: el
/// hilo y el streaming viven en providers, asi que moverlo de sitio no pierde
/// nada.
class AiAssistantPanel extends ConsumerStatefulWidget {
  const AiAssistantPanel({super.key, this.embedded = false});

  /// En `true` no se dibuja el boton de cerrar: no hay dialogo que cerrar, el
  /// panel vive en la pantalla.
  final bool embedded;

  @override
  ConsumerState<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

class _AiAssistantPanelState extends ConsumerState<AiAssistantPanel> {
  /// Se fuerza el paso al chat cuando el wizard termina, sin esperar a que el
  /// `FutureProvider` de estado se revalide.
  bool _forceChat = false;

  /// Evita disparar `_autoStart` dos veces por el mismo rebuild (el
  /// `FutureProvider` puede reconstruir varias veces mientras el arranque
  /// esta en vuelo).
  bool _autoStarting = false;

  /// Si el arranque automatico fallo, se cae al wizard normal — ahi el
  /// usuario ve el error real y puede reintentar a mano en vez de quedarse
  /// mirando un spinner que nunca progresa.
  bool _autoStartFailed = false;

  /// El usuario pidio "Cambiar de modelo" a proposito.
  ///
  /// Bug real que esto arregla: el boton solo hacia `_forceChat = false`,
  /// pero con una sesion ya viva `state.ready` sigue siendo `true` por su
  /// cuenta — la condicion `state.ready || _forceChat` daba `true` de
  /// cualquier forma y el wizard nunca se llegaba a ver. Con este flag el
  /// chat se oculta aunque `ready` este prendido.
  bool _wantWizard = false;

  /// Deja andando el motor que corresponde al **destino** del chat, sin pedir
  /// nada al usuario si ya esta en disco. No se dispara si el usuario pidio
  /// "Cambiar de modelo": ahi `state.installed` sigue siendo `true` (es el modelo
  /// VIEJO el que ya esta instalado) y auto-arrancarlo de nuevo anularia el pedido.
  ///
  /// **Mira el destino, no un `startSetup()` pelado.** Antes arrancaba el motor
  /// local siempre, y con un destino de nube (DeepSeek, la pasarela del stack) o
  /// Ollama eso cargaba el `llama-server` de llama.cpp igual —ocupando ~11 GiB de
  /// VRAM de mas— y encima reemplazaba el proveedor que el destino habia puesto.
  Future<void> _autoStart() async {
    if (_autoStarting) return;
    _autoStarting = true;
    try {
      final registry = ref.read(chatDestinationsProvider);
      final destination =
          registry.byId(ref.read(chatBackendProvider)) ??
          resolveStartupDestination(registry.destinations, registry.prefs);

      if (destination != null &&
          destination.kind != ChatDestinationKind.localModel) {
        // Nube, Ollama o Claude: no hay motor local que arrancar; `restoreDefault`
        // deja contestando ese destino.
        await ref.read(chatDestinationsProvider.notifier).restoreDefault();
      } else {
        // Local (o sin destino resuelto): arranca el motor local, con el modelo
        // del destino si lo hay.
        await ref
            .read(aiRepositoryProvider)
            .startSetup(modelId: destination?.modelId);
      }
      if (!mounted) return;
      setState(() => _forceChat = true);
      ref.invalidate(aiSetupStateProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoStartFailed = true);
    } finally {
      _autoStarting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(aiSetupStateProvider);
    // El registro de destinos: con el cargando no se decide que motor arrancar
    // (con la lista vacia se arrancaba el llama.cpp local por las dudas).
    final registry = ref.watch(chatDestinationsProvider);
    // Con Claude Code elegido **no hay motor local que esperar**: la respuesta
    // la da un corresponsal, no un modelo. Sin esta condicion, el dialogo
    // mandaria al wizard a descargar varios GB de un modelo que no se va a
    // usar, que es exactamente lo contrario de lo que el usuario pidio al
    // elegir ese destino.
    final viaCorrespondent =
        ref.watch(chatBackendProvider) == kClaudeCodeBackendId;
    final showChat =
        (state.value?.ready == true || _forceChat || viaCorrespondent) &&
        !_wantWizard;

    return Column(
      children: [
        // Encabezado
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                // Embebido en la pantalla principal es el asistente general;
                // en el dialogo sigue siendo "Crear con IA", que es lo que
                // ofrece abrirlo desde el deck.
                widget.embedded ? 'Asistente' : 'Crear con IA',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (showChat)
                IconButton(
                  tooltip: 'Conversaciones guardadas',
                  icon: const Icon(Icons.history),
                  onPressed: () => showConversationsSheet(context),
                ),
              if (showChat)
                IconButton(
                  tooltip: 'Cambiar de modelo',
                  icon: const Icon(Icons.tune),
                  onPressed: () => setState(() {
                    _wantWizard = true;
                    _forceChat = false;
                  }),
                ),
              if (!widget.embedded)
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text('No se pudo leer el estado del asistente: $error'),
              ),
            ),
            data: (state) {
              if (showChat) {
                return AiChatView(
                  providerLabel: state.providerLabel,
                  showProfileSwitch: widget.embedded,
                  showConversationsPanel: widget.embedded,
                );
              }
              // Se espera a que el registro de destinos termine de cargar para
              // decidir con el destino real delante, no con la lista vacia.
              if (registry.loading) return const _AutoStarting();
              if (state.installed && !_wantWizard && !_autoStartFailed) {
                _autoStart();
                return const _AutoStarting();
              }
              return AiSetupWizard(
                onReady: () {
                  if (!mounted) return;
                  setState(() {
                    _forceChat = true;
                    _wantWizard = false;
                  });
                  ref.invalidate(aiSetupStateProvider);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AutoStarting extends StatelessWidget {
  const _AutoStarting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: EmptyState(
        icon: Icons.bolt,
        title: 'Activando el asistente',
        message:
            'El modelo ya esta descargado — no hace falta elegir de nuevo.',
        leading: CircularProgressIndicator(),
      ),
    );
  }
}
