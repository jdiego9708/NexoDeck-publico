// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_conversations_dao.dart';

// ignore_for_file: type=lint
mixin _$ChatConversationsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $ChatConversationsTable get chatConversations =>
      attachedDatabase.chatConversations;
  $ChatMessagesTable get chatMessages => attachedDatabase.chatMessages;
  ChatConversationsDaoManager get managers => ChatConversationsDaoManager(this);
}

class ChatConversationsDaoManager {
  final _$ChatConversationsDaoMixin _db;
  ChatConversationsDaoManager(this._db);
  $$ChatConversationsTableTableManager get chatConversations =>
      $$ChatConversationsTableTableManager(
        _db.attachedDatabase,
        _db.chatConversations,
      );
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db.attachedDatabase, _db.chatMessages);
}
