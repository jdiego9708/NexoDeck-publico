import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/docs_inbox_repository.dart';
import '../domain/docs_inbox.dart';

final docsInboxRepositoryProvider = Provider<DocsInboxRepository>(
  (ref) => const DocsInboxRepository(),
);

class DocsInboxState {
  const DocsInboxState({this.inbox, this.error});

  /// `null` hasta la primera foto.
  final DocsInbox? inbox;

  /// El ultimo fallo al pedir la foto. Se conserva la foto anterior: un error
  /// pasajero no puede vaciar la bandeja que el usuario esta revisando.
  final String? error;

  int get pendingCount => inbox?.pendingProposals.length ?? 0;
}

/// La bandeja del buzon de documentacion.
///
/// **Se suscribe DIRECTO al `Stream` del puente, nunca con `ref.listen`**: dos
/// avisos seguidos tienen que dar dos refrescos. En cada aviso se pide la foto
/// entera; si llegan varios mientras se esta pidiendo, se juntan en una sola
/// vuelta mas, que ya trae todo lo que cambio.
///
/// Lo lee `main()` una vez al arrancar, despues de abrir el buzon: el stream de
/// Rust termina en el acto si el buzon todavia no existe.
class DocsInboxController extends Notifier<DocsInboxState> {
  StreamSubscription<int>? _subscription;
  bool _refreshing = false;
  bool _again = false;

  DocsInboxRepository get _repository => ref.read(docsInboxRepositoryProvider);

  @override
  DocsInboxState build() {
    _subscription = _repository.watchChanges().listen(
      (_) => refresh(),
      onError: (Object error) => _fail(error),
    );
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    scheduleMicrotask(refresh);
    return const DocsInboxState();
  }

  Future<void> refresh() async {
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _again = false;
        try {
          state = DocsInboxState(inbox: await _repository.snapshot());
        } catch (error) {
          _fail(error);
        }
      } while (_again);
    } finally {
      _refreshing = false;
    }
  }

  void _fail(Object error) {
    state = DocsInboxState(inbox: state.inbox, error: error.toString());
  }

  /// Toda accion refresca al terminar, haya ido bien o no: el estado real
  /// esta en Rust y un fallo a medias tambien puede haber cambiado algo.
  Future<T> _then<T>(Future<T> action) async {
    try {
      return await action;
    } finally {
      unawaited(refresh());
    }
  }

  Future<void> setWorkerEnabled(bool enabled) =>
      _then(_repository.setWorkerEnabled(enabled));

  Future<String> configJson() => _repository.configJson();

  Future<void> saveConfig(String json) => _then(_repository.saveConfig(json));

  Future<DocProposal> check(String id) => _then(_repository.check(id));

  Future<DocProposal> approve(DocProposal proposal) =>
      _then(_repository.approve(proposal.id, proposal.revision));

  Future<DocProposal> reject(String id, String? note) =>
      _then(_repository.reject(id, note));

  Future<DocProposal> regenerate(String id, String? note) =>
      _then(_repository.regenerate(id, note));

  Future<DocProposal> undo(String id) => _then(_repository.undo(id));
}

final docsInboxProvider = NotifierProvider<DocsInboxController, DocsInboxState>(
  DocsInboxController.new,
);
