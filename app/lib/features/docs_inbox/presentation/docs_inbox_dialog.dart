import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/interactive_card.dart';
import '../application/docs_inbox_controller.dart';
import '../domain/docs_inbox.dart';
import 'docs_note_dialog.dart';
import 'docs_projects_dialog.dart';
import 'widgets/operation_diff_card.dart';

/// El buzon de documentacion: las propuestas que preparo NexoDeck a partir de
/// los hallazgos de Claude Code, para aprobarlas, rechazarlas o rehacerlas.
Future<void> showDocsInboxDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DocsInboxDialog(),
  );
}

/// A partir de este ancho, la lista y el detalle van lado a lado.
const double _sideBySideWidth = 760;
const double _listWidth = 340;

class _DocsInboxDialog extends ConsumerStatefulWidget {
  const _DocsInboxDialog();

  @override
  ConsumerState<_DocsInboxDialog> createState() => _DocsInboxDialogState();
}

class _DocsInboxDialogState extends ConsumerState<_DocsInboxDialog> {
  String? _selectedId;

  /// Que se esta haciendo, para el indicador. `null` si nada.
  String? _busy;

  Future<void> _select(String id) async {
    setState(() => _selectedId = id);
    // Revalidar al abrir: si alguien toco el documento, la propuesta se ve ya
    // como "revisala otra vez" en vez de descubrirlo al aprobar.
    await _run('Comprobando los documentos…', () async {
      await ref.read(docsInboxProvider.notifier).check(id);
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = label);
    try {
      await action();
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _approve(DocProposal proposal) => _run('Aplicando…', () async {
    final result = await ref.read(docsInboxProvider.notifier).approve(proposal);
    _snack(switch (result.state) {
      DocProposalState.applied =>
        'Aplicada en ${result.files.join(', ')}. No se hizo commit.',
      DocProposalState.needsReview =>
        'Los documentos cambiaron desde la propuesta: no se escribió nada. '
            'Revísala otra vez y vuelve a aprobar.',
      _ => 'La propuesta ya no aplica sobre los documentos actuales.',
    }, error: result.state != DocProposalState.applied);
  });

  Future<void> _reject(DocProposal proposal) async {
    final note = await showDocsNoteDialog(
      context,
      title: 'Rechazar la propuesta',
      explanation: 'Los hallazgos quedan marcados como rechazados. La nota es '
          'opcional y queda guardada con ellos.',
      hint: 'Por qué no (opcional)',
      confirmLabel: 'Rechazar',
    );
    if (note == null) return;
    await _run('Rechazando…', () async {
      await ref
          .read(docsInboxProvider.notifier)
          .reject(proposal.id, note.isEmpty ? null : note);
    });
  }

  Future<void> _regenerate(DocProposal proposal) async {
    final note = await showDocsNoteDialog(
      context,
      title: 'Rehacer la propuesta',
      explanation: 'Se vuelve a pedir al modelo con los mismos hallazgos, los que '
          'hayan llegado mientras tanto y tu nota. Puede tardar un minuto; si '
          'falla, la propuesta actual queda como está.',
      hint: 'Qué cambiar, por ejemplo: "junta las dos secciones en una"',
      confirmLabel: 'Rehacer',
    );
    if (note == null) return;
    await _run('Rehaciendo la propuesta…', () async {
      await ref
          .read(docsInboxProvider.notifier)
          .regenerate(proposal.id, note.isEmpty ? null : note);
      _snack('Propuesta rehecha.');
    });
  }

  Future<void> _undo(DocProposal proposal) => _run('Deshaciendo…', () async {
    await ref.read(docsInboxProvider.notifier).undo(proposal.id);
    _snack('Documentos restaurados como estaban antes de aplicar.');
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(docsInboxProvider);
    final inbox = state.inbox;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Buzón de documentación',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => showDocsProjectsDialog(context),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Proyectos…'),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_busy != null) ...[
                const SizedBox(height: AppSpacing.xs),
                const LinearProgressIndicator(),
                Text(_busy!, style: theme.textTheme.bodySmall),
              ],
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    state.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: inbox == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            _body(inbox, constraints.maxWidth),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(DocsInbox inbox, double width) {
    final selected = _selectedId == null ? null : inbox.proposal(_selectedId!);
    final list = _InboxList(
      inbox: inbox,
      selectedId: _selectedId,
      onSelect: _select,
      onToggleWorker: (value) => _run(
        value ? 'Encendiendo el procesado…' : 'Apagando el procesado…',
        () => ref.read(docsInboxProvider.notifier).setWorkerEnabled(value),
      ),
    );
    final detail = selected == null
        ? const _EmptyDetail()
        : _ProposalDetail(
            inbox: inbox,
            proposal: selected,
            busy: _busy != null,
            onApprove: () => _approve(selected),
            onReject: () => _reject(selected),
            onRegenerate: () => _regenerate(selected),
            onUndo: () => _undo(selected),
            onBack: width < _sideBySideWidth
                ? () => setState(() => _selectedId = null)
                : null,
          );

    if (width >= _sideBySideWidth) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: _listWidth, child: list),
          const VerticalDivider(width: AppSpacing.lg),
          Expanded(child: detail),
        ],
      );
    }
    return selected == null ? list : detail;
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.inbox,
    required this.selectedId,
    required this.onSelect,
    required this.onToggleWorker,
  });

  final DocsInbox inbox;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<bool> onToggleWorker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = inbox.pendingProposals;
    final waiting = inbox.waitingFindings;
    final decided = inbox.decidedProposals.take(10).toList();

    return ListView(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: inbox.workerEnabled,
          onChanged: onToggleWorker,
          title: const Text('Procesado'),
          subtitle: Text(
            inbox.workerEnabled
                ? (inbox.working
                      ? 'Preparando una propuesta…'
                      : 'Modelo: ${inbox.remoteLabel ?? 'sin remoto configurado'}'
                            '${inbox.localFallback ? ', local si ya está levantado' : ''}')
                : 'Apagado: los hallazgos se guardan pero no se procesan',
          ),
        ),
        if (inbox.lastError != null)
          Text(
            inbox.lastError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        if (inbox.projects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'No hay proyectos configurados: Claude Code no tiene a dónde '
              'mandar hallazgos. Añádelos en "Proyectos…".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        _SectionTitle('Esperando tu decisión (${pending.length})'),
        if (pending.isEmpty)
          Text('Nada pendiente.', style: theme.textTheme.bodySmall),
        for (final proposal in pending)
          _ProposalTile(
            inbox: inbox,
            proposal: proposal,
            selected: proposal.id == selectedId,
            onTap: () => onSelect(proposal.id),
          ),
        if (waiting.isNotEmpty) ...[
          _SectionTitle('Hallazgos sin propuesta (${waiting.length})'),
          for (final finding in waiting) _FindingRow(finding: finding),
        ],
        if (decided.isNotEmpty) ...[
          const _SectionTitle('Recientes'),
          for (final proposal in decided)
            _ProposalTile(
              inbox: inbox,
              proposal: proposal,
              selected: proposal.id == selectedId,
              onTap: () => onSelect(proposal.id),
            ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.inbox,
    required this.proposal,
    required this.selected,
    required this.onTap,
  });

  final DocsInbox inbox;
  final DocProposal proposal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem =
        proposal.state == DocProposalState.stale ||
        proposal.state == DocProposalState.needsReview;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InteractiveCard(
        radius: AppRadius.chip,
        selected: selected,
        onTap: onTap,
        accent: problem ? theme.colorScheme.error : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${inbox.project(proposal.project)?.name ?? proposal.project} · '
                '${proposal.state.label}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: problem ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                proposal.summary.isEmpty ? '(sin resumen)' : proposal.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${proposal.operations.length} cambios · '
                '${proposal.origin == DocProposalOrigin.noteDigest ? 'nota ${proposal.note}' : '${proposal.findingIds.length} hallazgos'}'
                '${proposal.localModel ? ' · modelo local' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final DocFinding finding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = finding.state == DocFindingState.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(finding.title, style: theme.textTheme.bodyMedium),
          Text(
            '${finding.project} · ${finding.state.label}'
            '${finding.stateDetail == null ? '' : ': ${finding.stateDetail}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: failed ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Elige una propuesta para ver qué cambiaría en los documentos.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ProposalDetail extends StatelessWidget {
  const _ProposalDetail({
    required this.inbox,
    required this.proposal,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onUndo,
    this.onBack,
  });

  final DocsInbox inbox;
  final DocProposal proposal;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRegenerate;
  final VoidCallback onUndo;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final findings = inbox.findingsOf(proposal);
    final error = theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: 'Volver',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Text(
                '${inbox.project(proposal.project)?.name ?? proposal.project} · '
                '${proposal.state.label}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              'revisión ${proposal.revision} · ${proposal.modelLabel}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: ListView(
            children: [
              if (proposal.localModel)
                _Notice(
                  text: 'La preparó el modelo local: revísala con más cuidado.',
                  color: error,
                ),
              if (proposal.stateDetail != null)
                _Notice(
                  text: proposal.stateDetail!,
                  color: proposal.state == DocProposalState.rejected
                      ? theme.colorScheme.onSurfaceVariant
                      : error,
                ),
              for (final reason in proposal.staleReasons)
                _Notice(text: reason, color: error),
              if (proposal.summary.isNotEmpty)
                Text(proposal.summary, style: theme.textTheme.bodyLarge),
              for (final warning in proposal.warnings)
                _Notice(text: warning, color: theme.colorScheme.tertiary),

              if (proposal.origin == DocProposalOrigin.noteDigest) ...[
                const _SectionTitle('Nota'),
                Text(
                  'La preparó el asistente de notas a partir de '
                  '${proposal.note}. Qué hizo cada agente se ve en "Notas".',
                  style: theme.textTheme.bodySmall,
                ),
              ] else
                const _SectionTitle('Hallazgos'),
              for (final finding in findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${finding.kindLabel}: ${finding.title}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (finding.from != null)
                        Text('de ${finding.from}', style: theme.textTheme.bodySmall),
                      for (final evidence in finding.evidence)
                        Text(
                          '${evidence.label} ${evidence.text}'
                          '${evidence.source == null ? '' : ' — ${evidence.source}'}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              for (final item in proposal.unresolved)
                _Notice(
                  text: 'Sin encajar (${item.findingId}): ${item.why}',
                  color: theme.colorScheme.tertiary,
                ),

              _SectionTitle('Cambios (${proposal.operations.length})'),
              for (final operation in proposal.operations)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: OperationDiffCard(operation: operation),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (proposal.state.isPending) ...[
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('Rechazar'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onRegenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('Rehacer con una nota…'),
              ),
              FilledButton.icon(
                onPressed: busy || proposal.state == DocProposalState.stale
                    ? null
                    : onApprove,
                icon: const Icon(Icons.check),
                label: const Text('Aprobar y escribir'),
              ),
            ],
            if (proposal.state == DocProposalState.applied)
              OutlinedButton.icon(
                onPressed: busy ? null : onUndo,
                icon: const Icon(Icons.undo),
                label: const Text('Deshacer'),
              ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.badge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}
