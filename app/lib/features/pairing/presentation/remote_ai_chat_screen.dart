import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/features/ai_assistant/application/ai_live_runner.dart'
    show paramsForLiveDraft, renderLiveCommand;
import 'package:nexodeck/features/ai_assistant/domain/action_draft.dart';
import 'package:nexodeck/features/ai_assistant/domain/assistant_mode.dart';
import 'package:nexodeck/features/ai_assistant/domain/chat_entry.dart';
import 'package:nexodeck/features/ai_assistant/presentation/widgets/chat_bubble.dart';
import 'package:nexodeck/features/ai_assistant/presentation/widgets/confirm_dangerous_run_dialog.dart';
import 'package:nexodeck/features/ai_assistant/presentation/widgets/draft_trace_tile.dart';
import 'package:nexodeck/features/ai_assistant/presentation/widgets/tool_trace_tile.dart';
import 'package:nexodeck/features/actions/presentation/widgets/parameter_prompt_dialog.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_surface.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/connection_provider.dart';
import '../application/remote_ai_chat_provider.dart';

/// Abre el chat remoto: la MISMA conversacion que la PC ve en "Crear con
/// IA", mirada (y hablada) desde el telefono. El asistente sigue corriendo
/// unicamente en la PC -- este telefono nunca baja ni corre un modelo
/// propio, solo manda texto y recibe eventos por el cable (ver
/// `MessageV1::AiChatEvent`/`AiStatus`).
///
/// Marca `remoteAiChatScreenOpenProvider` mientras esta abierta y **no hace
/// nada si ya lo estaba** -- "preguntarle a la IA por un proceso"
/// (`process_panel.dart`) la llama sin saber si el usuario ya tenia el chat
/// abierto, y apilar una segunda pantalla encima seria confuso.
Future<void> showRemoteAiChatScreen(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(remoteAiChatScreenOpenProvider)) return;
  container.read(remoteAiChatScreenOpenProvider.notifier).state = true;
  try {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteAiChatScreen()));
  } finally {
    container.read(remoteAiChatScreenOpenProvider.notifier).state = false;
  }
}

class RemoteAiChatScreen extends ConsumerStatefulWidget {
  const RemoteAiChatScreen({super.key});

  @override
  ConsumerState<RemoteAiChatScreen> createState() => _RemoteAiChatScreenState();
}

class _RemoteAiChatScreenState extends ConsumerState<RemoteAiChatScreen> {
  final _entries = <ChatEntry>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();

  StreamSubscription<bridge.ConnectionEvent>? _subscription;

  /// Burbuja del asistente en construccion. A diferencia de la PC, nunca
  /// crece token a token (esos nunca cruzan el cable, ver el comentario de
  /// `MessageV1::AiChatEvent`): arranca vacia con `Typing` y se completa de
  /// una sola vez con `AssistantMessage`.
  AssistantEntry? _pending;

  bool _busy = false;
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    // Stream DIRECTO y no `ref.listen`: mismo motivo que en toda esta
    // pantalla remota y en `ai_chat_view.dart` -- Riverpod no vuelve a
    // notificar un valor `==` al anterior, y dos eventos identicos seguidos
    // (dos `ToolFinished` con el mismo resultado, por ejemplo) son
    // perfectamente posibles.
    _subscription = connectionEventStream(ref).listen(_handleConnectionEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _handleConnectionEvent(bridge.ConnectionEvent event) {
    if (!mounted) return;
    switch (event) {
      case bridge.ConnectionEvent_AiStatusReceived(:final ready):
        if (ready) setState(() => _activating = false);
      case bridge.ConnectionEvent_AiChatEventReceived(:final field0):
        _onChatEvent(field0);
      default:
        // A proposito NO exhaustivo, a diferencia de `main.dart`/
        // `connected_device_screen.dart` (que SI listan cada variante,
        // porque son el despacho canonico de cada rol): esta pantalla es
        // una tercera suscriptora angosta del mismo stream, y el resto de
        // los ~18 eventos restantes (catalogo, metricas, procesos...) ya
        // los atiende quien corresponde en otro lado.
        break;
    }
  }

  void _onChatEvent(bridge.AiRemoteChatEvent event) {
    setState(() {
      switch (event) {
        case bridge.AiRemoteChatEvent_UserMessage(:final text):
          // Lo que escribio el usuario de la PC, no el de este telefono: lo
          // propio ya se agrego al tocar enviar, ver `_send`.
          _entries.add(UserEntry(text));

        case bridge.AiRemoteChatEvent_Typing():
          _pending ??= _appendPending();

        case bridge.AiRemoteChatEvent_AssistantMessage(:final text):
          final target = _pending;
          if (target != null) {
            target
              ..text = text
              ..isStreaming = false;
          } else if (text.trim().isNotEmpty) {
            _entries.add(AssistantEntry(text: text, isStreaming: false));
          }
          _pending = null;

        case bridge.AiRemoteChatEvent_ToolStarted(:final name, :final summary):
          _closePending();
          _entries.add(ToolEntry(name: name, summary: summary));

        case bridge.AiRemoteChatEvent_ToolFinished(
          :final name,
          :final ok,
          :final summary,
        ):
          final pending = _entries.whereType<ToolEntry>().lastWhere(
            (entry) => entry.name == name && !entry.done,
            orElse: () {
              final entry = ToolEntry(name: name, summary: name);
              _entries.add(entry);
              return entry;
            },
          );
          pending
            ..done = true
            ..ok = ok
            ..result = summary;

        case bridge.AiRemoteChatEvent_DraftReady(:final draft):
          _closePending();
          _entries.add(DraftEntry(ActionDraft.fromRemote(draft)));

        case bridge.AiRemoteChatEvent_TurnDone():
          _closePending();
          _busy = false;

        case bridge.AiRemoteChatEvent_Failed(:final detail):
          _closePending();
          _entries.add(ErrorEntry(detail));
          _busy = false;
      }
    });
    _scrollToBottom();
  }

  AssistantEntry _appendPending() {
    final entry = AssistantEntry(text: '');
    _entries.add(entry);
    return entry;
  }

  void _closePending() {
    final target = _pending;
    if (target == null) return;
    target.isStreaming = false;
    if (target.isEmpty) _entries.remove(target);
    _pending = null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _entries.add(UserEntry(text));
      _busy = true;
    });
    _inputController.clear();
    _inputFocus.requestFocus();
    _scrollToBottom();

    try {
      await ref.read(connectionRepositoryProvider).sendAiMessage(text);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries.add(ErrorEntry('$error'));
        _busy = false;
      });
    }
  }

  Future<void> _activate() async {
    setState(() => _activating = true);
    try {
      await ref.read(connectionRepositoryProvider).sendAiActivate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activating = false;
        _entries.add(ErrorEntry('$error'));
      });
    }
  }

  /// "Guardar como boton": el borrador viaja tal cual, `{{parametros}}`
  /// incluidos -- guardar un boton NO es correrlo, asi que no hay nada que
  /// resolver aca. La PC lo crea sin volver a preguntar, mismo modelo de
  /// confianza que `ExecuteAction`.
  Future<void> _applyDraft(DraftEntry entry) async {
    try {
      await ref
          .read(connectionRepositoryProvider)
          .sendAiApplyDraft(entry.draft.toRemote());
      if (!mounted) return;
      setState(() => entry.outcome = DraftOutcome.saved);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    }
  }

  /// "Ejecutar ahora": a diferencia de guardar, esto SI necesita resolver
  /// `{{parametros}}` a valores concretos antes de mandarlo -- la PC corre
  /// el comando que le llega tal cual, sin volver a preguntar nada (mismo
  /// criterio que `ai_live_runner.dart` del lado PC, con el mismo dialogo
  /// de parametros y la misma confirmacion extra para pasos peligrosos/
  /// admin, reusados sin cambios porque `ActionDraft` es un tipo Dart puro).
  ///
  /// El progreso en vivo de cada paso se ve por la notificacion de siempre
  /// (`RunToastHost`, montado tambien en Android) -- no se intenta reflejar
  /// paso a paso adentro de esta conversacion: correlacionar cada
  /// `ActionRunUpdate` que llega con el borrador que lo disparo agregaria
  /// una heuristica fragil para un beneficio chico, la notificacion ya
  /// cubre lo que importa.
  Future<void> _runDraft(DraftEntry entry) async {
    final draft = entry.draft;
    final needsExtraConfirm =
        draft.risk == DraftRisk.dangerous ||
        draft.steps.any((step) => step.requiresAdmin);
    if (needsExtraConfirm) {
      final confirmed = await showConfirmDangerousRunDialog(context, draft);
      if (!confirmed) return;
    }
    if (!mounted) return;

    final params = paramsForLiveDraft(draft);
    var values = const <String, String>{};
    if (params.isNotEmpty) {
      final entered = await showParameterPromptDialog(
        context,
        title: draft.name,
        parameters: params,
      );
      if (entered == null) return; // cancelado
      values = entered;
    }
    if (!mounted) return;

    final resolved = ActionDraft(
      name: draft.name,
      description: draft.description,
      icon: draft.icon,
      colorHex: draft.colorHex,
      summary: draft.summary,
      risk: draft.risk,
      steps: [
        for (final step in draft.steps)
          DraftStep(
            name: step.name,
            description: step.description,
            actionType: step.actionType,
            command: step.command,
            resolvedCommand: renderLiveCommand(step, values),
            terminalType: step.terminalType,
            requiresAdmin: step.requiresAdmin,
            showTerminalWindow: step.showTerminalWindow,
            workingDirectory: step.workingDirectory,
            delayMsAfter: step.delayMsAfter,
            risk: step.risk,
            riskNotes: step.riskNotes,
            autoSubscribe: step.autoSubscribe,
          ),
      ],
    );

    setState(() => entry.outcome = DraftOutcome.running);
    try {
      await ref
          .read(connectionRepositoryProvider)
          .sendAiRunDraft(resolved.toRemote());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo ejecutar: $error')));
    }
  }

  void _discardDraft(DraftEntry entry) {
    setState(() => entry.outcome = DraftOutcome.discarded);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(remoteAiStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Asistente de IA')),
      body: !status.enabled
          ? const EmptyState(
              icon: Icons.smart_toy_outlined,
              title: 'El asistente esta apagado',
              message:
                  'Se desactivo el switch de arriba en la PC. Actívalo ahí '
                  'para volver a usar el chat desde acá.',
            )
          : !status.ready
          ? _buildActivate()
          : _buildChat(scheme),
    );
  }

  Widget _buildActivate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyState(
              icon: Icons.bolt,
              title: 'El asistente no esta activo',
              message: 'Se activa una sola vez por sesion en la PC.',
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _activating ? null : _activate,
              icon: _activating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_activating ? 'Activando...' : 'Activar asistente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(ColorScheme scheme) {
    return Column(
      children: [
        Expanded(
          child: _entries.isEmpty
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Conversa con el asistente de tu PC',
                  message: 'Lo que escribas acá lo ve (y contesta) la PC.',
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) => _entryWidget(_entries[index]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(border: Border(top: AppSurface.hairline(scheme))),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        _send();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _busy
                            ? 'El asistente esta trabajando...'
                            : 'Escribile al asistente',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  tooltip: 'Enviar',
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _entryWidget(ChatEntry entry) => switch (entry) {
    UserEntry(:final text) => ChatBubble(text: text, isUser: true),
    AssistantEntry(:final text, :final isStreaming) => ChatBubble(
      text: text,
      isUser: false,
      isStreaming: isStreaming,
    ),
    ToolEntry() => ToolTraceTile(entry: entry),
    DraftEntry() => DraftTraceTile(
      entry: entry,
      // Siempre las dos acciones juntas -- ver el comentario del tope del
      // archivo: `liveExecution` es el unico de los dos modos de
      // `DraftPreviewCard` que muestra "Ejecutar ahora" Y "Guardar como
      // boton" en la misma fila.
      mode: AssistantMode.liveExecution,
      onToggle: () => setState(() => entry.expanded = !entry.expanded),
      onApply: () => _applyDraft(entry),
      onRun: entry.outcome == null ? () => _runDraft(entry) : null,
      onDiscard: entry.outcome == null ? () => _discardDraft(entry) : null,
    ),
    ErrorEntry(:final detail) => _RemoteErrorTile(detail: detail),
  };
}

class _RemoteErrorTile extends StatelessWidget {
  const _RemoteErrorTile({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SelectableText(detail, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
