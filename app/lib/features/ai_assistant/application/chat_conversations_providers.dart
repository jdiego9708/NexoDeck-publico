import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/data/local/daos/chat_conversations_dao.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../core/di/database_provider.dart';

const _kConversationsPanelCollapsedKey = 'conversations_panel_collapsed';

/// El DAO de las conversaciones guardadas.
///
/// Compartido por la hoja (`conversations_sheet.dart`) y el panel compacto
/// (`conversations_panel.dart`): dos proveedores para lo mismo serian la misma
/// decision escrita dos veces.
final chatConversationsDaoProvider = Provider<ChatConversationsDao>(
  (ref) => ChatConversationsDao(ref.watch(databaseProvider)),
);

/// Las activas, de la mas reciente a la mas vieja.
final activeConversationsProvider =
    StreamProvider.autoDispose<List<ChatConversation>>(
      (ref) => ref.watch(chatConversationsDaoProvider).watchActive(),
    );

/// Las archivadas, de la mas reciente a la mas vieja.
final archivedConversationsProvider =
    StreamProvider.autoDispose<List<ChatConversation>>(
      (ref) => ref.watch(chatConversationsDaoProvider).watchArchived(),
    );

/// Si el panel compacto de conversaciones --dentro del panel del chat del
/// centro de control-- esta plegado.
///
/// Preferencia de usuario en `app_settings` (clave/valor), mismo patron que
/// `actions_panel_collapsed`: el valor inicial real lo lee `main()` antes de
/// `runApp` y se inyecta con `overrideWith`.
final conversationsPanelCollapsedProvider = StateProvider<bool>((ref) => false);

final conversationsPanelControllerProvider =
    Provider<ConversationsPanelController>((ref) {
      final db = ref.watch(databaseProvider);
      return ConversationsPanelController(ref, AppSettingsDao(db));
    });

class ConversationsPanelController {
  ConversationsPanelController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  Future<void> setCollapsed(bool collapsed) async {
    _ref.read(conversationsPanelCollapsedProvider.notifier).state = collapsed;
    await _dao.setValue(_kConversationsPanelCollapsedKey, collapsed.toString());
  }
}

/// Lee la ultima preferencia guardada antes de `runApp`.
Future<bool> readInitialConversationsPanelCollapsed(AppSettingsDao dao) async {
  return await dao.getValue(_kConversationsPanelCollapsedKey) == 'true';
}
