import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../application/action_groups_provider.dart';
import '../application/actions_provider.dart';
import '../data/actions_repository.dart';
import '../domain/deck_action.dart';
import '../domain/placeholders.dart';
import 'widgets/action_icons.dart';

/// A partir de este largo, el campo de comando (3 lineas) deja de mostrar
/// el panorama completo y conviene ofrecer la vista ampliada.
const _kLongCommandChars = 180;

/// Valores con los que abrir el editor ya cargado, sin que exista todavia
/// ninguna fila en la base.
///
/// Lo usa el asistente de IA: el borrador que propone se muestra en el editor
/// de siempre y **el usuario lo guarda con el flujo normal**. Asi el camino de
/// la IA reusa toda la validacion que ya existe y nada se persiste sin que un
/// humano lo haya leido. No confundir con [DeckAction] (`existing`), que es una
/// accion que ya vive en Drift y se esta editando.
class ActionEditorSeed {
  const ActionEditorSeed({
    required this.name,
    this.description,
    required this.icon,
    required this.colorHex,
    required this.actionType,
    this.commandTemplate,
    this.requiresAdmin = false,
    this.terminalType,
    this.showTerminalWindow = false,
    this.pasteToActiveWindow = false,
    this.groupId,
    this.parameters = const [],
    this.macroSteps = const [],
    this.autoSubscribe,
  });

  final String name;
  final String? description;
  final String icon;
  final String colorHex;
  final ActionType actionType;
  final String? commandTemplate;
  final bool requiresAdmin;
  final TerminalType? terminalType;
  final bool showTerminalWindow;
  final bool pasteToActiveWindow;
  final String? groupId;
  final List<ActionParamDraft> parameters;
  final AutoSubscribeConfig? autoSubscribe;

  /// Ids de acciones que ya existen en la base. Para una cadena generada por la
  /// IA, las hojas se crean **antes** de abrir el editor (dentro de una
  /// transaccion) justamente para que estos ids sean reales.
  final List<MacroStepDraft> macroSteps;
}

/// Abre el editor de acciones.
///
/// Devuelve `true` si se guardo. Lo necesita el camino de la IA: si el usuario
/// cancela el editor de una macro, hay que borrar las hojas que se crearon para
/// armarla, o el deck queda con botones que nadie pidio.
Future<bool> showActionEditorSheet(
  BuildContext context, {
  DeckAction? existing,
  ActionEditorSeed? seed,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ActionEditorSheet(existing: existing, seed: seed),
  );
  return saved ?? false;
}

class _ParamDraftState {
  _ParamDraftState({
    String? key,
    String? label,
    ParamInputType? inputType,
    String? defaultValue,
    List<String> options = const [],
  }) : keyController = TextEditingController(text: key),
       labelController = TextEditingController(text: label),
       defaultController = TextEditingController(text: defaultValue),
       optionsController = TextEditingController(text: options.join(', ')),
       inputType = inputType ?? ParamInputType.text;

  final TextEditingController keyController;
  final TextEditingController labelController;
  final TextEditingController defaultController;

  /// Opciones separadas por coma. Se le pide asi al usuario (y no como el
  /// JSON que guarda la tabla) porque escribir `["A","B"]` a mano en un
  /// campo de texto es una fuente de errores de sintaxis para nada.
  final TextEditingController optionsController;

  ParamInputType inputType;

  List<String> get options => optionsController.text
      .split(',')
      .map((o) => o.trim())
      .where((o) => o.isNotEmpty)
      .toList();
}

/// Un paso de macro en el editor. Guarda la `Key` estable que necesita
/// `ReorderableListView` -- usar el indice como key hace que al reordenar
/// Flutter reuse el widget equivocado y el estado (el campo de pausa) salte
/// de fila.
class _MacroStepDraftState {
  _MacroStepDraftState({required this.stepActionId, int delayMs = 0})
    : delayController = TextEditingController(text: '$delayMs'),
      key = UniqueKey();

  final String stepActionId;
  final TextEditingController delayController;
  final Key key;

  int get delayMs => int.tryParse(delayController.text.trim()) ?? 0;
}

class _ActionEditorSheet extends ConsumerStatefulWidget {
  const _ActionEditorSheet({this.existing, this.seed});

  final DeckAction? existing;
  final ActionEditorSeed? seed;

  @override
  ConsumerState<_ActionEditorSheet> createState() => _ActionEditorSheetState();
}

class _ActionEditorSheetState extends ConsumerState<_ActionEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  /// Precedencia: la accion que se esta editando gana sobre la semilla, y la
  /// semilla sobre el valor por defecto. Nunca hay las dos a la vez, pero el
  /// orden deja el caso explicito en vez de depender de que nadie las combine.
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? widget.seed?.name,
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? widget.seed?.description,
  );
  late final _commandController = TextEditingController(
    text: widget.existing?.commandTemplate ?? widget.seed?.commandTemplate,
  );
  late String _icon = widget.existing?.icon ?? widget.seed?.icon ?? 'bolt';
  late String _colorHex =
      widget.existing?.colorHex ?? widget.seed?.colorHex ?? kActionColorPalette.first;
  late ActionType _actionType =
      widget.existing?.actionType ?? widget.seed?.actionType ?? ActionType.clipboard;
  late TerminalType _terminalType =
      widget.existing?.terminalType ??
      widget.seed?.terminalType ??
      TerminalType.defaultShell;
  late bool _requiresAdmin =
      widget.existing?.requiresAdmin ?? widget.seed?.requiresAdmin ?? false;
  late bool _showTerminalWindow =
      widget.existing?.showTerminalWindow ?? widget.seed?.showTerminalWindow ?? false;
  late bool _pasteToActiveWindow =
      widget.existing?.pasteToActiveWindow ??
      widget.seed?.pasteToActiveWindow ??
      false;
  late String? _groupId = widget.existing?.groupId ?? widget.seed?.groupId;

  /// De un boton guardado o de un borrador de la IA — el usuario revisa y
  /// confirma cualquiera de los dos igual, nada se guarda solo.
  AutoSubscribeConfig? get _seededAutoSubscribe =>
      widget.existing?.autoSubscribe ?? widget.seed?.autoSubscribe;

  late bool _autoSubscribeEnabled = _seededAutoSubscribe != null;
  late final _autoSubscribeBaseUrlController = TextEditingController(
    text: _seededAutoSubscribe?.baseUrl,
  );
  late final _autoSubscribeHubPathController = TextEditingController(
    text: _seededAutoSubscribe?.hubPath,
  );
  late final _autoSubscribeInvokeMethodController = TextEditingController(
    text: _seededAutoSubscribe?.invokeMethod ?? 'SubscribeToJob',
  );
  late final _autoSubscribeJsonFieldController = TextEditingController(
    text: _seededAutoSubscribe?.jsonField ?? 'job_id',
  );
  late bool _autoSubscribeAllowInvalidCert =
      _seededAutoSubscribe?.allowInvalidCert ?? false;
  late final List<_ParamDraftState> _params = widget.existing != null
      ? [
          for (final p in widget.existing!.parameters)
            _ParamDraftState(
              key: p.key,
              label: p.label,
              inputType: p.inputType,
              defaultValue: p.defaultValue,
              options: p.options,
            ),
        ]
      : [
          for (final p in widget.seed?.parameters ?? const <ActionParamDraft>[])
            _ParamDraftState(
              key: p.key,
              label: p.label,
              inputType: p.inputType,
              defaultValue: p.defaultValue,
              options: p.options,
            ),
        ];
  late final List<_MacroStepDraftState> _steps = widget.existing != null
      ? [
          for (final s in widget.existing!.macroSteps)
            _MacroStepDraftState(
              stepActionId: s.stepActionId,
              delayMs: s.delayMsAfter,
            ),
        ]
      : [
          for (final s in widget.seed?.macroSteps ?? const <MacroStepDraft>[])
            _MacroStepDraftState(
              stepActionId: s.stepActionId,
              delayMs: s.delayMsAfter,
            ),
        ];

  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final theme = Theme.of(context);
    final accent = colorFromHex(_colorHex);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _AccentBadge(icon: iconForName(_icon), color: accent),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        isEditing ? 'Editar acción' : 'Nueva acción',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel('Datos generales'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel('Tipo y comando'),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<ActionType>(
                  segments: const [
                    ButtonSegment(
                      value: ActionType.clipboard,
                      label: Text('Portapapeles'),
                      icon: Icon(Icons.content_paste),
                    ),
                    ButtonSegment(
                      value: ActionType.terminal,
                      label: Text('Terminal'),
                      icon: Icon(Icons.terminal),
                    ),
                    ButtonSegment(
                      value: ActionType.macro,
                      label: Text('Macro'),
                      icon: Icon(Icons.playlist_play_rounded),
                    ),
                  ],
                  selected: {_actionType},
                  onSelectionChanged: (s) => setState(() => _actionType = s.first),
                ),
                // Una macro no tiene comando propio: su "comando" son los
                // pasos. Mostrar el campo igual invitaria a escribir algo
                // que despues nunca se ejecuta.
                if (_isMacro) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _MacroStepsEditor(
                    steps: _steps,
                    editingActionId: widget.existing?.id,
                    onAdd: _addMacroStep,
                    onRemove: (step) => setState(() => _steps.remove(step)),
                    onReorder: _reorderMacroSteps,
                  ),
                ] else
                  ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _commandController,
                    decoration: InputDecoration(
                      labelText: _actionType == ActionType.clipboard
                          ? 'Texto a copiar (usa {{variable}} para parámetros)'
                          : 'Comando (usa {{variable}} para parámetros)',
                      // Icono para ampliar: un comando de curl con JSON, o
                      // una cadena de scripts encadenados con `&&`, no entra
                      // comodo en 3 lineas y este campo no puede crecer sin
                      // empujar el resto del formulario fuera de la vista.
                      suffixIcon: IconButton(
                        tooltip: 'Ampliar',
                        icon: const Icon(Icons.open_in_full, size: 18),
                        onPressed: _openFullscreenCommandEditor,
                      ),
                    ),
                    maxLines: 3,
                    // Redibuja para que la advertencia de placeholders sin
                    // declarar aparezca mientras se escribe, no recien al
                    // guardar.
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  // Con el comando largo, 3 lineas visibles no alcanzan para
                  // orientarse (donde esta el placeholder que falta, donde
                  // termina un paso encadenado). El aviso solo aparece
                  // cuando hace falta, no en cada accion.
                  if (_commandController.text.length > _kLongCommandChars) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _openFullscreenCommandEditor,
                        icon: const Icon(Icons.open_in_full, size: 14),
                        label: Text(
                          'Comando largo (${_commandController.text.length} '
                          'caracteres) · Ver completo',
                        ),
                      ),
                    ),
                  ],
                ],
                if (_actionType == ActionType.clipboard) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _SwitchCard(
                    title: 'Pegar en la ventana activa',
                    subtitle: _pasteToActiveWindow
                        ? 'Devuelve el foco a la app que lo tenía antes del '
                              'clic y manda Ctrl+V. El texto queda copiado '
                              'igual si el pegado no se puede hacer.'
                        : 'Solo copia al portapapeles. Vos pegás después, '
                              'donde quieras.',
                    value: _pasteToActiveWindow,
                    onChanged: (v) => setState(() => _pasteToActiveWindow = v),
                  ),
                ],
                if (_actionType == ActionType.terminal) ...[
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<TerminalType>(
                    initialValue: _terminalType,
                    decoration: const InputDecoration(labelText: 'Tipo de terminal'),
                    items: const [
                      DropdownMenuItem(
                        value: TerminalType.defaultShell,
                        child: Text('Por defecto'),
                      ),
                      DropdownMenuItem(
                        value: TerminalType.powershell,
                        child: Text('PowerShell'),
                      ),
                      DropdownMenuItem(value: TerminalType.cmd, child: Text('CMD')),
                      DropdownMenuItem(
                        value: TerminalType.bash,
                        child: Text('Bash'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _terminalType = v!),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SwitchCard(
                    title: 'Requiere administrador',
                    value: _requiresAdmin,
                    onChanged: (v) => setState(() => _requiresAdmin = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SwitchCard(
                    title: 'Abrir una terminal real',
                    subtitle: _showTerminalWindow
                        ? 'Solo para comandos que piden datos por teclado '
                              '(ssh, npm init). No se captura la salida ni se '
                              'avisa si falla.'
                        : 'El comando corre dentro de NexoDeck y su salida, '
                              'duración y resultado se muestran como '
                              'notificación.',
                    value: _showTerminalWindow,
                    onChanged: (v) => setState(() => _showTerminalWindow = v),
                  ),
                  // Solo en modo capturado: sin salida capturada no hay JSON
                  // que leer, asi que en modo ventana esto no puede
                  // ofrecerse aunque el usuario lo haya prendido antes.
                  if (!_showTerminalWindow) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _SwitchCard(
                      title: 'Suscribirse al terminar',
                      subtitle: _autoSubscribeEnabled
                          ? 'Si el comando termina bien, se lee el campo de '
                                'abajo de su salida (JSON) y se arranca una '
                                'suscripción SignalR con ese valor.'
                          : 'Para encadenar un comando que lanza un job '
                                '(devuelve un id) con su progreso en vivo, '
                                'sin copiar el id a mano.',
                      value: _autoSubscribeEnabled,
                      onChanged: (v) => setState(() => _autoSubscribeEnabled = v),
                    ),
                    if (_autoSubscribeEnabled) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _autoSubscribeBaseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'URL base del hub',
                          hintText: 'http://localhost:5242',
                        ),
                        validator: (v) => (_autoSubscribeEnabled &&
                                (v == null || v.trim().isEmpty))
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _autoSubscribeHubPathController,
                        decoration: const InputDecoration(
                          labelText: 'Ruta del hub',
                          hintText: '/hubs/plant-training-progress',
                        ),
                        validator: (v) => (_autoSubscribeEnabled &&
                                (v == null || v.trim().isEmpty))
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _autoSubscribeInvokeMethodController,
                        decoration: const InputDecoration(
                          labelText: 'Método a invocar',
                          hintText: 'SubscribeToJob',
                        ),
                        validator: (v) => (_autoSubscribeEnabled &&
                                (v == null || v.trim().isEmpty))
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _autoSubscribeJsonFieldController,
                        decoration: const InputDecoration(
                          labelText: 'Campo con el id en la respuesta',
                          hintText: 'job_id',
                        ),
                        validator: (v) => (_autoSubscribeEnabled &&
                                (v == null || v.trim().isEmpty))
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SwitchCard(
                        title: 'Aceptar certificado TLS inválido',
                        subtitle:
                            'Solo para https con certificado autofirmado de '
                            'desarrollo.',
                        value: _autoSubscribeAllowInvalidCert,
                        onChanged: (v) =>
                            setState(() => _autoSubscribeAllowInvalidCert = v),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel('Apariencia'),
                const SizedBox(height: AppSpacing.sm),
                _IconPicker(
                  selected: _icon,
                  accent: accent,
                  onSelected: (i) => setState(() => _icon = i),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ColorPicker(
                  selected: _colorHex,
                  onSelected: (c) => setState(() => _colorHex = c),
                ),
                const SizedBox(height: AppSpacing.sm),
                Consumer(
                  builder: (context, ref, _) {
                    final groups = ref.watch(actionGroupsListProvider).value ?? const [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _groupId,
                      decoration: const InputDecoration(labelText: 'Grupo'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin grupo')),
                        for (final group in groups)
                          DropdownMenuItem(value: group.id, child: Text(group.name)),
                      ],
                      onChanged: (v) => setState(() => _groupId = v),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                // Una macro no declara parametros propios: hereda los de
                // sus pasos, deduplicados por nombre de variable (ver
                // `promptParametersFor`). Ofrecer aca una lista propia
                // haria creer que se puede pasar un valor a un paso que no
                // lo declara.
                if (_isMacro)
                  _InfoNote(
                    icon: Icons.tune_rounded,
                    text: 'Al ejecutarla se pedirán los parámetros de sus '
                        'pasos. Si varios pasos usan la misma variable, se '
                        'pregunta una sola vez.',
                  )
                else ...[
                  Row(
                    children: [
                      const _SectionLabel('Parámetros'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _params.add(_ParamDraftState())),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Agregar'),
                      ),
                    ],
                  ),
                  for (final param in _params)
                    _ParamRow(
                      state: param,
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => _params.remove(param)),
                    ),
                  if (_undeclared.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _InfoNote(
                      icon: Icons.warning_amber_rounded,
                      emphasize: true,
                      text: _undeclared.length == 1
                          ? 'Usas {{${_undeclared.first}}} en el comando pero '
                                'no lo declaraste como parámetro: se va a '
                                'ejecutar con ese texto tal cual.'
                          : 'Usas ${_undeclared.map((k) => '{{$k}}').join(', ')} '
                                'en el comando pero no los declaraste como '
                                'parámetros: se van a ejecutar con ese texto '
                                'tal cual.',
                      action: TextButton(
                        onPressed: _declareMissing,
                        child: const Text('Declararlos'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      isEditing ? 'Guardar cambios' : 'Crear acción',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: AppDuration.collapse).slideY(
        begin: 0.08,
        end: 0,
        duration: AppDuration.collapse,
        curve: AppCurves.standard,
      ),
    );
  }

  /// Abre el comando en una pantalla completa, propia para editar texto
  /// largo. Comparte el mismo `TextEditingController` que el campo chico
  /// del formulario -- lo que se escribe alla ya queda en este, sin copiar
  /// nada de vuelta al cerrar. El `setState` de despues es lo que redibuja
  /// la advertencia de placeholders y el aviso de "comando largo" con el
  /// texto que haya quedado.
  Future<void> _openFullscreenCommandEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _FullscreenTextEditor(
          controller: _commandController,
          title: _actionType == ActionType.clipboard
              ? 'Texto a copiar'
              : 'Comando',
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  bool get _isMacro => _actionType == ActionType.macro;

  /// `null` cuando el switch esta apagado, no es terminal, o esta en modo
  /// ventana (sin salida capturada no hay JSON del que leer nada).
  AutoSubscribeConfig? get _autoSubscribeDraft {
    if (!_autoSubscribeEnabled ||
        _actionType != ActionType.terminal ||
        _showTerminalWindow) {
      return null;
    }
    return AutoSubscribeConfig(
      baseUrl: _autoSubscribeBaseUrlController.text.trim(),
      hubPath: _autoSubscribeHubPathController.text.trim(),
      invokeMethod: _autoSubscribeInvokeMethodController.text.trim(),
      jsonField: _autoSubscribeJsonFieldController.text.trim(),
      allowInvalidCert: _autoSubscribeAllowInvalidCert,
    );
  }

  /// Placeholders del comando sin parametro que los complete. Una macro no
  /// tiene comando propio, asi que no aplica.
  List<String> get _undeclared => _isMacro
      ? const []
      : undeclaredPlaceholders(
          _commandController.text,
          _params.map((p) => p.keyController.text),
        ).toList();

  /// Agrega de una los parametros que faltan, con la variable ya cargada
  /// (la etiqueta cae al mismo nombre si no se toca). Es el atajo obvio: si
  /// la app puede decir cuales faltan, puede crearlos.
  void _declareMissing() {
    setState(() {
      for (final key in _undeclared) {
        _params.add(_ParamDraftState(key: key, label: key));
      }
    });
  }

  void _addMacroStep(String actionId) {
    setState(() => _steps.add(_MacroStepDraftState(stepActionId: actionId)));
  }

  void _reorderMacroSteps(int oldIndex, int newIndex) {
    setState(() {
      // `ReorderableListView` reporta el destino contando la fila que se
      // esta moviendo, asi que hay que descontarla al bajar.
      if (newIndex > oldIndex) newIndex -= 1;
      _steps.insert(newIndex, _steps.removeAt(oldIndex));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Una macro sin pasos se guardaria "bien" y despues no haria nada al
    // tocarla, sin ningun error: se corta aca.
    if (_isMacro && _steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un paso a la macro')),
      );
      return;
    }
    setState(() => _saving = true);

    final repository = ref.read(actionsRepositoryProvider);
    final drafts = _isMacro
        ? const <ActionParamDraft>[]
        : [
            for (final p in _params)
              if (p.keyController.text.trim().isNotEmpty)
                ActionParamDraft(
                  key: p.keyController.text.trim(),
                  label: p.labelController.text.trim().isEmpty
                      ? p.keyController.text.trim()
                      : p.labelController.text.trim(),
                  inputType: p.inputType,
                  defaultValue: p.defaultController.text.trim().isEmpty
                      ? null
                      : p.defaultController.text.trim(),
                  options: p.inputType == ParamInputType.select
                      ? p.options
                      : const [],
                ),
          ];
    final stepDrafts = _isMacro
        ? [
            for (final s in _steps)
              MacroStepDraft(
                stepActionId: s.stepActionId,
                delayMsAfter: s.delayMs,
              ),
          ]
        : const <MacroStepDraft>[];

    final existing = widget.existing;
    try {
      if (existing == null) {
        await repository.createAction(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          icon: _icon,
          colorHex: _colorHex,
          actionType: _actionType,
          // Una macro no guarda plantilla: si se convirtio desde terminal,
          // dejar el comando viejo en la fila solo genera confusion al
          // volver a editarla.
          commandTemplate: _isMacro ? null : _commandController.text,
          requiresAdmin: _requiresAdmin,
          terminalType: _actionType == ActionType.terminal
              ? _terminalType
              : null,
          showTerminalWindow: _showTerminalWindow,
          pasteToActiveWindow: _pasteToActiveWindow,
          groupId: _groupId,
          autoSubscribe: _autoSubscribeDraft,
          parameters: drafts,
          macroSteps: stepDrafts,
        );
      } else {
        await repository.updateAction(
          existing,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          icon: _icon,
          colorHex: _colorHex,
          actionType: _actionType,
          commandTemplate: _isMacro ? null : _commandController.text,
          requiresAdmin: _requiresAdmin,
          terminalType: _actionType == ActionType.terminal
              ? _terminalType
              : null,
          showTerminalWindow: _showTerminalWindow,
          pasteToActiveWindow: _pasteToActiveWindow,
          groupId: _groupId,
          autoSubscribe: _autoSubscribeDraft,
          parameters: drafts,
          macroSteps: stepDrafts,
        );
      }
    } on NestedMacroException catch (e) {
      // El selector de pasos ya filtra las macros, asi que llegar aca
      // significa que la accion se convirtio en macro entre que se abrio el
      // editor y se guardo. Se informa en vez de fallar en silencio.
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }

    // `true` = se guardo. El camino de la IA lo usa para saber si tiene que
    // borrar las hojas que creo para armar una macro que el usuario cancelo.
    if (mounted) Navigator.of(context).pop(true);
  }

}

/// Encabezado de seccion en mayusculas con letter-spacing, para separar
/// visualmente los grupos del formulario sin necesitar dividers duros.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDuration.state,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = this.subtitle;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          Expanded(
            child: subtitle == null
                ? Text(title)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.state,
    required this.onRemove,
    required this.onChanged,
  });

  final _ParamDraftState state;
  final VoidCallback onRemove;

  /// Se llama al cambiar el tipo: la fila de opciones solo existe para
  /// `select`, asi que el editor tiene que redibujarse.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: state.keyController,
                  decoration: const InputDecoration(labelText: 'variable'),
                  // Al escribir la variable deja de "faltar": la
                  // advertencia se recalcula.
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: state.labelController,
                  decoration: const InputDecoration(labelText: 'Etiqueta'),
                ),
              ),
              IconButton(
                tooltip: 'Quitar parámetro',
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<ParamInputType>(
                  initialValue: state.inputType,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(
                      value: ParamInputType.text,
                      child: Text('Texto'),
                    ),
                    DropdownMenuItem(
                      value: ParamInputType.number,
                      child: Text('Número'),
                    ),
                    DropdownMenuItem(
                      value: ParamInputType.select,
                      child: Text('Lista'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    state.inputType = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: state.defaultController,
                  decoration: const InputDecoration(
                    labelText: 'Valor por defecto',
                  ),
                ),
              ),
              // Reserva el ancho del boton de quitar de la fila de arriba
              // para que las dos filas queden alineadas.
              const SizedBox(width: 48),
            ],
          ),
          if (state.inputType == ParamInputType.select) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: state.optionsController,
                    decoration: const InputDecoration(
                      labelText: 'Opciones',
                      helperText: 'Separadas por coma: staging, producción',
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Editor de los pasos de una macro: lista reordenable de acciones ya
/// existentes, cada una con su pausa posterior.
class _MacroStepsEditor extends ConsumerWidget {
  const _MacroStepsEditor({
    required this.steps,
    required this.editingActionId,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  final List<_MacroStepDraftState> steps;

  /// Id de la accion que se esta editando, para no ofrecerse a si misma
  /// como paso (una macro que se llama a si misma no termina nunca).
  final String? editingActionId;

  final ValueChanged<String> onAdd;
  final ValueChanged<_MacroStepDraftState> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(actionsListProvider).value ?? const <DeckAction>[];
    final byId = {for (final a in all) a.id: a};
    // Solo acciones simples: no hay macros anidadas (lo valida tambien el
    // repositorio, pero ofrecerlas y despues rechazarlas seria cruel).
    final candidates = all
        .where((a) => a.actionType != ActionType.macro && a.id != editingActionId)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('Pasos'),
            const Spacer(),
            TextButton.icon(
              onPressed: candidates.isEmpty
                  ? null
                  : () => _pickStep(context, candidates),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar paso'),
            ),
          ],
        ),
        if (candidates.isEmpty)
          const _InfoNote(
            icon: Icons.info_outline_rounded,
            text: 'Primero crea acciones de portapapeles o terminal: una '
                'macro se arma encadenando acciones que ya existen.',
          )
        else if (steps.isEmpty)
          const _InfoNote(
            icon: Icons.playlist_add_rounded,
            text: 'Sin pasos todavía. Se ejecutarán en orden, esperando la '
                'pausa indicada entre uno y el siguiente.',
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            // Vive dentro del `SingleChildScrollView` del formulario: el
            // scroll lo maneja el padre.
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: onReorder,
            children: [
              for (final (index, step) in steps.indexed)
                _MacroStepRow(
                  key: step.key,
                  index: index,
                  isLast: index == steps.length - 1,
                  step: step,
                  action: byId[step.stepActionId],
                  onRemove: () => onRemove(step),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _pickStep(
    BuildContext context,
    List<DeckAction> candidates,
  ) async {
    final chosen = await showDialog<DeckAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Agregar paso'),
        children: [
          for (final action in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(action),
              child: Row(
                children: [
                  Icon(
                    iconForName(action.icon),
                    size: 18,
                    color: colorFromHex(action.colorHex),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(action.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null) onAdd(chosen.id);
  }
}

class _MacroStepRow extends StatelessWidget {
  const _MacroStepRow({
    super.key,
    required this.index,
    required this.isLast,
    required this.step,
    required this.action,
    required this.onRemove,
  });

  final int index;
  final bool isLast;
  final _MacroStepDraftState step;
  final DeckAction? action;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final action = this.action;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Icon(Icons.drag_indicator, size: 18),
            ),
          ),
          Text(
            '${index + 1}.',
            style: AppText.numeric(Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (action != null)
            Icon(
              iconForName(action.icon),
              size: 18,
              color: colorFromHex(action.colorHex),
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              // El paso guarda un id; si la accion no esta en la lista es
              // que se borro (y el `onDelete: cascade` de Drift ya se va a
              // llevar la fila).
              action?.name ?? 'Acción eliminada',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: action == null
                  ? TextStyle(color: scheme.error)
                  : null,
            ),
          ),
          // La pausa del ultimo paso no se aplica (no hay nada despues), asi
          // que no se pide.
          if (!isLast)
            SizedBox(
              width: 96,
              child: TextFormField(
                controller: step.delayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pausa',
                  suffixText: 'ms',
                  isDense: true,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Quitar paso',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Nota informativa dentro del formulario: explica una regla del modelo
/// (por que una macro no tiene comando, o por que no declara parametros)
/// en el lugar donde el usuario se la pregunta.
class _InfoNote extends StatelessWidget {
  const _InfoNote({
    required this.icon,
    required this.text,
    this.action,
    this.emphasize = false,
  });

  final IconData icon;
  final String text;

  /// Boton opcional al pie (ej. "Declararlos"): una advertencia que ademas
  /// ofrece el arreglo vale mas que una que solo informa.
  final Widget? action;

  /// Advertencia (tinte de error) en vez de nota neutra.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = emphasize ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: emphasize
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
          ?action,
        ],
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final String selected;
  final Color accent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in kActionIcons.entries)
          GestureDetector(
            onTap: () => onSelected(entry.key),
            child: AnimatedContainer(
              duration: AppDuration.selection,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected == entry.key
                    ? accent.withValues(alpha: 0.18)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                  color: selected == entry.key ? accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                entry.value,
                size: 18,
                color: selected == entry.key ? accent : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final hex in kActionColorPalette)
          GestureDetector(
            onTap: () => onSelected(hex),
            child: AnimatedContainer(
              duration: AppDuration.selection,
              curve: AppCurves.press,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorFromHex(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == hex
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected == hex
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Pantalla completa para editar texto largo (el comando o el texto de
/// portapapeles). Usa el MISMO `TextEditingController` que el campo chico
/// del formulario: escribir aca ya escribe alla, sin ningun paso de
/// "guardar y volver".
class _FullscreenTextEditor extends StatelessWidget {
  const _FullscreenTextEditor({required this.controller, required this.title});

  final TextEditingController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          // Monoespaciada: es un comando, no prosa -- alinear columnas
          // (flags, rutas, `&&` encadenados) se lee mejor sin proporcional.
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Comando o texto completo',
          ),
        ),
      ),
    );
  }
}
