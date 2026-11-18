import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_surface.dart';
import '../../actions/application/actions_provider.dart';
import '../../stack/application/stack_controller.dart';
import '../../stack/domain/stack_profile.dart';
import '../../stack/presentation/profile_switch.dart';
import '../application/ai_draft_applier.dart';
import '../application/ai_live_runner.dart';
import '../application/ai_profiles_controller.dart';
import '../application/ai_providers.dart';
import '../domain/action_draft.dart';
import '../domain/assistant_mode.dart';

import '../application/claude_code_chat_controller.dart';
import '../application/chat_conversation_controller.dart';
import '../application/chat_destinations_controller.dart';
import '../application/new_conversation.dart';
import '../domain/chat_backend.dart';
import '../domain/chat_destination.dart';
import '../domain/chat_entry.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_welcome.dart';
import 'widgets/conversations_panel.dart';
import 'widgets/draft_trace_tile.dart';
import 'widgets/profiles_section.dart';
import 'widgets/tool_trace_tile.dart';

/// La conversacion con el asistente.
///
/// El estado vive aca (no se persiste: no aporta al objetivo de armar un boton
/// y costaria una migracion de Drift), y los eventos se consumen con
/// **suscripcion directa al `Stream`**, cancelada en `dispose()`. Ver la nota
/// larga en `ai_providers.dart` sobre por que `ref.listen` no sirve para esto.
class AiChatView extends ConsumerStatefulWidget {
  const AiChatView({
    super.key,
    required this.providerLabel,
    this.showProfileSwitch = false,
    this.showConversationsPanel = false,
  });

  final String? providerLabel;

  /// Muestra el switch de perfil del stack (Perfil A / B / C /
  /// Apagado) debajo del composer. Solo en la pantalla de escritorio: en el
  /// dialogo, y en el movil, el stack no aplica.
  final bool showProfileSwitch;

  /// Muestra el panel compacto de conversaciones guardadas al lado del hilo.
  /// Solo en el centro de control: el dialogo del asistente sigue con la hoja
  /// de conversaciones (icono de historial).
  final bool showConversationsPanel;

  @override
  ConsumerState<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends ConsumerState<AiChatView> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();

  /// La conversacion **no vive aca**: vive en `chatConversationProvider`, que
  /// sigue anotando aunque este dialogo este cerrado y recibe tambien lo que
  /// se escribe desde el telefono. Ver la cabecera de ese controlador.
  ChatTranscript get _conversation => ref.watch(chatConversationProvider);
  ChatConversationController get _chat =>
      ref.read(chatConversationProvider.notifier);
  List<ChatEntry> get _entries => _conversation.entries;
  bool get _busy => _conversation.busy;

  /// `false` (preguntar antes de correr) es el default a proposito: un modo
  /// que ejecuta solo tiene que ser una eleccion explicita, no algo con lo que
  /// alguien se encuentre sin buscarlo. Ver `_canAutoRun` por la excepcion de
  /// `Dangerous`/admin, que nunca se saltea aunque esto este prendido.
  bool _autoRun = false;

  /// `true` justo despues de que `DraftReady` dispara en modo en vivo: el
  /// texto que el modelo escribe a continuacion ("el boton va a
  /// ejecutar...") no se muestra. Se corta desde el primer token — recien
  /// saltear el evento `AssistantMessage` final llegaria tarde, el texto ya
  /// se hubiera visto aparecer letra por letra.

  /// Ultimo `nonce` de `aiPendingPromptProvider` ya procesado -- evita
  /// mandar el mismo pedido dos veces si `build` vuelve a correr con el
  /// mismo valor todavia puesto (`ref.listen` solo dispara en el cambio,
  /// pero el chequeo en `initState` es aparte y podria pisarlo).
  int? _consumedPromptNonce;

  @override
  void initState() {
    super.initState();
    // Las suscripciones a los eventos viven en el controlador, que sobrevive a
    // cerrar este dialogo. Aca solo se le prestan las dos cosas que son de la
    // pantalla: en que modo esta, y donde correr un borrador.
    _chat
      ..mode = AssistantMode.liveExecution
      ..onDraftReady = _onDraftReady;
    _scrollController.addListener(_onScroll);
    _pushDeckContext();

    // Si alguien pidio "preguntale esto a la IA" (el boton del panel de
    // procesos) ANTES de que este dialogo llegara a abrirse, el pedido
    // queda esperando en el provider -- se toma aca, apenas el chat esta
    // listo para mandar.
    final pending = ref.read(aiPendingPromptProvider);
    if (pending != null && pending.nonce != _consumedPromptNonce) {
      _consumedPromptNonce = pending.nonce;
      _inputController.text = pending.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    }
  }

  @override
  void dispose() {
    // Al cerrarse deja de autoejecutar: sin dialogo no hay donde mostrar la
    // ejecucion ni quien confirme. El borrador se sigue anotando igual.
    _chat.onDraftReady = null;
    _inputController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Le pasa al asistente los botones que ya existen para que no proponga
  /// duplicados.
  Future<void> _pushDeckContext() async {
    final actions = ref.read(actionsListProvider).value;
    if (actions == null || actions.isEmpty) return;
    try {
      await ref.read(aiRepositoryProvider).setDeckContext(actions);
    } catch (_) {
      // El contexto del deck es una ayuda, no un requisito: si falla, el
      // asistente igual funciona.
    }
  }

  /// Solo en modo en vivo, con "Ejecutar automaticamente" prendido, y solo
  /// si nada en el borrador exige la confirmacion extra (`Dangerous` o
  /// algun paso con `requiresAdmin`) — esa confirmacion sigue apareciendo
  /// SIEMPRE, incluso en automatico: es la unica red de seguridad real de
  /// este modo, y saltearla ahi seria indistinguible de no tener modo
  /// "preguntar" en absoluto.
  bool _canAutoRun(ActionDraft draft) {
    if (!_autoRun) return false;
    if (draft.risk == DraftRisk.dangerous) return false;
    if (draft.steps.any((step) => step.requiresAdmin)) return false;
    return true;
  }

  /// Cuanto tiene que faltar para el final para seguir considerando que el
  /// usuario "esta abajo". Sin este margen, arrastrarlo de vuelta cada vez
  /// que lee algo mas arriba se siente tan tosco como el salto que arregla
  /// esta funcion.
  static const _stickToBottomThreshold = 80.0;

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <=
        _stickToBottomThreshold;
  }

  /// El usuario esta siguiendo el final del hilo: lo nuevo lo arrastra. Se
  /// apaga al subir a leer y se vuelve a prender al bajar, como en cualquier
  /// chat de IA.
  bool _stick = true;

  /// Hay algo nuevo abajo y el usuario no esta mirando el final: se le avisa
  /// con el badge en vez de moverle la pantalla.
  bool _newBelow = false;

  /// Cuantas entradas hay y cuanto mide el texto en curso. Sirve para saber si
  /// lo que llego es contenido nuevo o solo un cambio de `busy`.
  (int, int) _signature(List<ChatEntry> entries) {
    final last = entries.isEmpty ? null : entries.last;
    return (entries.length, last is AssistantEntry ? last.text.length : 0);
  }

  void _onScroll() {
    final near = _isNearBottom;
    if (near == _stick) {
      if (near && _newBelow) setState(() => _newBelow = false);
      return;
    }
    setState(() {
      _stick = near;
      if (near) _newBelow = false;
    });
  }

  /// Se llama en cada cambio de la conversacion (un token, un mensaje). Si el
  /// usuario esta abajo, se sigue el final; si no, se marca el badge.
  ///
  /// Abrir otra conversacion (cambia la primera entrada) cuenta como empezar de
  /// nuevo: se muestra el final, no el badge.
  void _onTranscriptChanged(List<ChatEntry> before, List<ChatEntry> after) {
    final replaced =
        before.isNotEmpty &&
        after.isNotEmpty &&
        !identical(before.first, after.first);
    if (replaced) {
      setState(() {
        _stick = true;
        _newBelow = false;
      });
      _scrollToBottom();
      return;
    }

    if (_stick) {
      _scrollToBottom(animated: false);
      return;
    }
    if (after.isNotEmpty && _signature(before) != _signature(after)) {
      setState(() => _newBelow = true);
    }
  }

  /// `animated: false` (el caso de cada token) salta directo en vez de
  /// reiniciar una curva de 200 ms que a 39 tok/s nunca llega a terminar —
  /// eso es lo que se sentia "tosco". Las adiciones menos frecuentes (un
  /// mensaje nuevo, una herramienta) siguen animadas.
  ///
  /// No decide si conviene: eso lo hace quien llama (`_stick`). Antes llevaba
  /// el guard de "solo si esta cerca del final", que le impedia bajar cuando
  /// el usuario acababa de mandar un mensaje.
  void _scrollToBottom({bool animated = true}) {
    // Un frame despues, cuando la lista ya crecio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: AppDuration.state,
          curve: AppCurves.standard,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _busy) return;
    // Con el stack arrancando no hay nada que preguntar todavia: la pasarela da
    // 503. El campo ya esta deshabilitado; esto cierra el camino del atajo
    // (Enter) y del pedido pendiente.
    if (widget.showProfileSwitch && ref.read(stackStartingProvider)) return;

    final toCorrespondent =
        ref.read(chatBackendProvider) == kClaudeCodeBackendId;

    // La burbuja del usuario la anota `sendAiMessageBroadcast`, que es por
    // donde pasan **las dos puntas**: lo que se escribe aca y lo que llega del
    // telefono. Anotarla tambien aca la duplicaria.
    //
    // Con el corresponsal NO se bloquea el campo: tarda minutos y dejar la
    // entrada inerte todo ese rato impediria encolar una segunda pregunta o
    // corregir la primera. Con un modelo si, que contesta en segundos.
    _chat.setBusy(!toCorrespondent);
    _inputController.clear();
    _inputFocus.requestFocus();
    setState(() {
      _stick = true;
      _newBelow = false;
    });
    _scrollToBottom();

    try {
      // Reenvia el eco a los telefonos conectados y recien despues reparte
      // segun el destino elegido -- ver `sendAiMessageBroadcast`.
      final askId = await sendAiMessageBroadcast(ref.read, text);

      if (toCorrespondent && askId != null && mounted) {
        // Una espera sin explicacion es indistinguible de que no pasara nada.
        // El texto depende de si algun oyente recogio algo alguna vez: sin
        // eso, "tarda" y "no hay nadie" se verian igual.
        final seen = ref.read(claudeCodeChatProvider).listenerEverSeen;
        _chat.addCorrespondentWaiting(
          askId,
          correspondentWaitingMessage(
            CorrespondentAskStatus.queued,
            listenerEverSeen: seen,
          ),
        );
        _scrollToBottom();
      }
    } catch (error) {
      if (!mounted) return;
      _chat.addError('$error');
    }
  }

  /// Cambia de destino. Activarlo puede fallar (una clave que ya no vale, un
  /// Ollama que se cerro) y **eso se dice**: dejar el selector cambiado sobre
  /// un destino que no arranco seria mentir sobre quien va a contestar.
  /// Aplica un modo del stack desde el menu `MODO…`: arranca/para vLLM **y**
  /// deja contestando el motor del slot de Pensamiento del perfil, via
  /// `activateProfile` (que reemplaza el motor anterior). Asi elegir un perfil de
  /// nube apaga el llama.cpp local y libera su VRAM, en vez de dejarlo cargado.
  /// «Apagado» solo toca el stack, que es lo unico que apaga.
  Future<String?> _applyProfile(StackProfile profile) {
    if (profile == StackProfile.apagado) {
      return ref.read(stackControllerProvider).select(StackProfile.apagado);
    }
    return activateProfile(ref, profile.profileName!);
  }

  Future<void> _reset() async {
    await startNewConversation(ref);
    if (!mounted) return;
    setState(() {
      _stick = true;
      _newBelow = false;
    });
  }

  /// El borrador llego mientras el dialogo esta abierto: aca se decide si se
  /// autoejecuta. Con el cerrado esto no esta puesto y el borrador solo queda
  /// anotado.
  void _onDraftReady(DraftEntry entry) {
    if (_canAutoRun(entry.draft)) _runDraft(entry);
  }

  Future<void> _applyDraft(DraftEntry entry) async {
    final saved = await applyDraft(context, ref, entry.draft);
    if (!mounted || !saved) return;
    entry.outcome = DraftOutcome.saved;
    _chat.touch();
  }

  Future<void> _runDraft(DraftEntry entry) async {
    // Se marca ANTES de que termine de correr, no despues: sin esto, tocar
    // "Ejecutar ahora" dos veces rapido (el primer click todavia no
    // deshabilito el boton mientras se espera el dialogo de confirmacion)
    // dispararia la misma cadena por duplicado.
    entry
      ..outcome = DraftOutcome.running
      ..isExecuting = true;
    _chat.touch();
    final results = await runDraftLive(
      context,
      ref,
      entry.draft,
      // Los pasos quedan DENTRO del borrador (`entry.liveSteps`), no como
      // entradas sueltas de `_entries`: asi un solo toggle (el de
      // `DraftTraceTile`) controla a la vez la tarjeta y su ejecucion, en
      // vez de que cada paso tenga su propia fila siempre visible.
      onEntry: (chatEntry) {
        if (!mounted) return;
        entry.liveSteps.add(chatEntry);
        _chat.touch();
      },
    );
    if (mounted) {
      entry.isExecuting = false;
      _chat.touch();
    }

    // Vacio = no llego a correr nada (cancelo el dialogo de confirmacion o
    // el de parametros): no hay salida real que resumir.
    if (results.isEmpty) return;
    await _summarizeRun(entry.draft, results);
  }

  /// Le pide al modelo que lea la salida REAL (no la que escribio antes de
  /// correr, cuando todavia no sabia que iba a pasar) y la resuma. Nunca se
  /// muestra como si el usuario lo hubiera escrito — el usuario no escribio
  /// esto, y mostrarlo en una burbuja propia seria mentirle.
  Future<void> _summarizeRun(
    ActionDraft draft,
    List<LiveStepResult> results,
  ) async {
    // Bug real: esto se dispara apenas termina de correr, y el turno que
    // propuso el borrador todavia puede seguir "ocupado" escribiendo su
    // frase de cierre ("el boton va a ejecutar...") — un `git status`
    // captura mas rapido de lo que tarda esa frase en generarse. Sin
    // esperar, `sendMessage` explota con `AiError.Busy` (o, con el chequeo
    // de antes, se salteaba en silencio y el resumen nunca aparecia).
    while (mounted && _busy) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    _chat.setBusy(true);
    try {
      await ref
          .read(aiRepositoryProvider)
          .sendMessage(buildSummaryPrompt(draft, results));
    } catch (error) {
      if (!mounted) return;
      _chat.addError('$error');
    }
  }

  void _discardDraft(DraftEntry entry) {
    entry.outcome = DraftOutcome.discarded;
    _chat.touch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Los modelos elegidos de cada perfil, para el menu de modo. Es `watch` y no
    // `read`: sin observar el provider, el catalogo de `models.json` no se carga
    // nunca y el menu mostraba el **rol** (`router`, `fast`) en vez del nombre
    // del modelo. Con el watch se carga al montar el chat y el menu ya lo tiene.
    final profilesState = widget.showProfileSwitch
        ? ref.watch(aiProfilesProvider)
        : null;

    // Si el perfil elegido tiene roles locales: con el de nube, una pasarela
    // caida no es un fallo que anunciar. `null` en «Apagado» o si no se sabe.
    final selectedProfileName = ref
        .watch(selectedStackProfileProvider)
        .profileName;
    final selectedProfileConfig =
        (profilesState == null || selectedProfileName == null)
        ? null
        : profilesState.config.forProfile(selectedProfileName);
    final localModelsExpected = selectedProfileConfig == null
        ? null
        : (selectedProfileConfig.router.isStack ||
              selectedProfileConfig.thinking.isStack);

    // Mientras el stack arranca (o para) no se pregunta: la pasarela devuelve
    // 503 y el usuario no tendria como saber que la culpa es del arranque. Solo
    // aplica al chat de escritorio, que es donde vive el switch.
    final stackStarting =
        widget.showProfileSwitch && ref.watch(stackStartingProvider);

    // Caso "el dialogo ya estaba abierto": `initState` solo mira el pedido
    // pendiente una vez, al montarse. Si llega uno nuevo mientras este
    // widget ya esta vivo (otra pregunta desde el panel de procesos, con
    // el chat abierto), este es quien lo toma.
    ref.listen(aiPendingPromptProvider, (previous, next) {
      if (next == null || next.nonce == _consumedPromptNonce) return;
      _consumedPromptNonce = next.nonce;
      _inputController.text = next.text;
      _send();
    });

    // El final del hilo: seguir si el usuario esta abajo, avisar con el badge
    // si esta leyendo mas arriba. Ver `_onTranscriptChanged`.
    ref.listen(chatConversationProvider, (previous, next) {
      if (previous == null) return;
      _onTranscriptChanged(previous.entries, next.entries);
    });

    final chat = Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _entries.isEmpty
                    ? ChatWelcome(
                        onPick: (text) {
                          _inputController.text = text;
                          _inputFocus.requestFocus();
                        },
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) =>
                            _entryWidget(_entries[index]),
                      ),
              ),
              if (_newBelow && _entries.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.md,
                  child: Center(
                    child: _NewMessagesBadge(
                      onTap: () {
                        setState(() {
                          _stick = true;
                          _newBelow = false;
                        });
                        _scrollToBottom();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Composer
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border(top: AppSurface.hairline(scheme)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  // Enter envia, Shift+Enter hace salto de linea. Con un
                  // `Focus(onKeyEvent:)` --como estaba-- el campo se volvia
                  // intocable: ese `Focus` es un nodo ENFOCABLE de mas, y
                  // cuando se queda con el foco primario las acciones de
                  // edicion (Backspace, flechas) se resuelven hacia arriba y
                  // nunca llegan a `EditableText`, mientras que las letras si
                  // entran (van por el canal de texto). `CallbackShortcuts` no
                  // enfoca: solo intercepta la tecla y deja el resto igual.
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
                  },
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    enabled: !_busy && !stackStarting,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: stackStarting
                          ? 'Arrancando el perfil…'
                          : _busy
                          ? 'El asistente esta trabajando...'
                          : 'Escribí tu pregunta o pedido…',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (_busy)
                IconButton.filledTonal(
                  tooltip: 'Cancelar',
                  onPressed: () => ref.read(aiRepositoryProvider).cancelTurn(),
                  icon: const Icon(Icons.stop_rounded),
                )
              else
                IconButton.filled(
                  tooltip: stackStarting ? 'Arrancando el perfil' : 'Enviar',
                  onPressed: stackStarting ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
            ],
          ),
        ),

        // Preguntar / Automatico, debajo de la caja de texto: decide que pasa
        // con el PROXIMO borrador. Se puede cambiar con el asistente
        // trabajando: no reinicia nada, y `_canAutoRun` lo relee cada vez.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.pan_tool_outlined, size: 16),
                  label: Text('Preguntar'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.bolt, size: 16),
                  label: Text('Automatico'),
                ),
              ],
              selected: {_autoRun},
              onSelectionChanged: (selection) =>
                  setState(() => _autoRun = selection.first),
            ),
          ),
        ),

        // El perfil del stack (A / B / C / Apagado), en el menu sutil de
        // `ProfileSwitch`. `describe` saca de la config del asistente los
        // modelos **elegidos** de cada perfil, asi el renglon los muestra en
        // tiempo real (locales o de la nube) en vez de los de la receta.
        if (widget.showProfileSwitch && profilesState != null)
          ProfileSwitch(
            describe: (profile) =>
                describeProfileModels(profilesState, profile),
            onSelect: _applyProfile,
            localModelsExpected: localModelsExpected,
          ),

        // Pie
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Quien contesta es **solo lectura**: lo decide el perfil del
              // stack (`MODO…` / «Levantar»), que instala el motor del slot de
              // Pensamiento. Antes habia un selector manual acá, un sistema
              // paralelo que confundia (podia decir una cosa y contestar otra).
              _CurrentDestination(
                activeId: ref.watch(chatBackendProvider),
                fallbackLabel: widget.providerLabel,
              ),
              const Spacer(),
              if (_entries.isNotEmpty)
                TextButton.icon(
                  onPressed: _busy ? null : _reset,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Empezar de nuevo'),
                ),
            ],
          ),
        ),
      ],
    );

    // El indice de conversaciones guardadas, al lado del hilo. Solo en el
    // centro de control (`embedded`): el dialogo del asistente sigue con su
    // hoja de siempre, para no meterle una columna a un panel de 900 px.
    if (!widget.showConversationsPanel) return chat;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConversationsPanel(),
        const VerticalDivider(width: 1),
        Expanded(child: chat),
      ],
    );
  }

  Widget _entryWidget(ChatEntry entry) => switch (entry) {
    UserEntry(:final text, :final fromPhone) => ChatBubble(
      text: text,
      isUser: true,
      fromPhone: fromPhone,
    ),
    AssistantEntry(:final text, :final isStreaming) => ChatBubble(
      text: text,
      isUser: false,
      isStreaming: isStreaming,
    ),
    ToolEntry() => ToolTraceTile(entry: entry),
    DraftEntry() => DraftTraceTile(
      entry: entry,
      mode: AssistantMode.liveExecution,
      onToggle: () => setState(() => entry.expanded = !entry.expanded),
      onApply: () => _applyDraft(entry),
      onRun: () => _runDraft(entry),
      onDiscard: () => _discardDraft(entry),
    ),
    ErrorEntry(:final detail) => _ErrorTile(detail: detail),
  };
}

/// Muestra **quien contesta** el chat. Es **solo lectura**: el motor lo elige el
/// perfil del stack (su slot de Pensamiento) desde `MODO…` o «Levantar», que es
/// lo que lo instala. Antes habia un menu manual acá, un sistema paralelo al de
/// los perfiles que podia decir una cosa y contestar otra.
class _CurrentDestination extends ConsumerWidget {
  const _CurrentDestination({
    required this.activeId,
    required this.fallbackLabel,
  });

  final String activeId;

  /// Lo que dice el motor que esta activo, para cuando el registro todavia no
  /// termino de cargar.
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = ref.watch(chatDestinationsProvider).byId(activeId);
    final current =
        active?.label ??
        (fallbackLabel?.isNotEmpty == true ? fallbackLabel! : 'Sin destino');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconFor(active?.kind), size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            'Contesta: $current',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(ChatDestinationKind? kind) => switch (kind) {
    ChatDestinationKind.correspondent => Icons.hub_outlined,
    ChatDestinationKind.remote => Icons.cloud_outlined,
    ChatDestinationKind.ollama => Icons.dns_outlined,
    ChatDestinationKind.localModel => Icons.memory_outlined,
    null => Icons.help_outline,
  };
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.detail});

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
            child: SelectableText(
              detail,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// La pildora de "hay mensajes nuevos abajo".
///
/// Aparece cuando llega algo con el usuario leyendo mas arriba, y lo baja al
/// final al tocarla. Es lo que hacen los chats de IA en vez de arrastrarle la
/// pantalla a quien esta leyendo.
class _NewMessagesBadge extends StatelessWidget {
  const _NewMessagesBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primaryContainer,
      elevation: 2,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward,
                size: 16,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Mensajes nuevos',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
