import 'package:nexodeck/src/rust/api/docs.dart' as bridge;

import '../domain/docs_inbox.dart';

/// Envuelve el puente del buzon de documentacion. Existe para que ninguna
/// pantalla llame al bridge directo y para poder sustituirlo en los tests, que
/// no cargan `RustLib`.
class DocsInboxRepository {
  const DocsInboxRepository();

  /// Abre el buzon y arranca el trabajador. Idempotente. Devuelve la carpeta.
  Future<String> init({required bool aiEnabled}) =>
      bridge.docsInboxInit(aiEnabled: aiEnabled);

  Future<void> setAiEnabled(bool enabled) =>
      bridge.docsSetAiEnabled(enabled: enabled);

  Future<DocsInbox> snapshot() async =>
      DocsInbox.fromBridge(await bridge.docsInboxSnapshot());

  /// Un numero por cada cambio. El numero no significa nada salvo que nunca se
  /// repite seguido: es lo que evita que dos avisos se confundan en uno.
  Stream<int> watchChanges() =>
      bridge.watchDocsInboxEvents().map((event) => event.seq);

  Future<void> setWorkerEnabled(bool enabled) =>
      bridge.setDocsWorkerEnabled(enabled: enabled);

  Future<String> configJson() => bridge.docsInboxConfigJson();

  Future<void> saveConfig(String json) => bridge.saveDocsInboxConfig(json: json);

  Future<DocProposal> check(String id) async =>
      DocProposal.fromBridge(await bridge.checkDocsProposal(id: id));

  Future<DocProposal> approve(String id, int revision) async =>
      DocProposal.fromBridge(
        await bridge.approveDocsProposal(id: id, revision: revision),
      );

  Future<DocProposal> reject(String id, String? note) async =>
      DocProposal.fromBridge(await bridge.rejectDocsProposal(id: id, note: note));

  Future<DocProposal> regenerate(String id, String? note) async =>
      DocProposal.fromBridge(
        await bridge.regenerateDocsProposal(id: id, note: note),
      );

  Future<DocProposal> undo(String id) async =>
      DocProposal.fromBridge(await bridge.undoDocsProposal(id: id));
}
