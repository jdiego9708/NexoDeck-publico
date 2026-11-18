// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AiRemoteChatEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiRemoteChatEvent()';
}


}

/// @nodoc
class $AiRemoteChatEventCopyWith<$Res>  {
$AiRemoteChatEventCopyWith(AiRemoteChatEvent _, $Res Function(AiRemoteChatEvent) __);
}


/// Adds pattern-matching-related methods to [AiRemoteChatEvent].
extension AiRemoteChatEventPatterns on AiRemoteChatEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AiRemoteChatEvent_UserMessage value)?  userMessage,TResult Function( AiRemoteChatEvent_Typing value)?  typing,TResult Function( AiRemoteChatEvent_AssistantMessage value)?  assistantMessage,TResult Function( AiRemoteChatEvent_ToolStarted value)?  toolStarted,TResult Function( AiRemoteChatEvent_ToolFinished value)?  toolFinished,TResult Function( AiRemoteChatEvent_DraftReady value)?  draftReady,TResult Function( AiRemoteChatEvent_TurnDone value)?  turnDone,TResult Function( AiRemoteChatEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AiRemoteChatEvent_UserMessage() when userMessage != null:
return userMessage(_that);case AiRemoteChatEvent_Typing() when typing != null:
return typing(_that);case AiRemoteChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that);case AiRemoteChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that);case AiRemoteChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that);case AiRemoteChatEvent_DraftReady() when draftReady != null:
return draftReady(_that);case AiRemoteChatEvent_TurnDone() when turnDone != null:
return turnDone(_that);case AiRemoteChatEvent_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AiRemoteChatEvent_UserMessage value)  userMessage,required TResult Function( AiRemoteChatEvent_Typing value)  typing,required TResult Function( AiRemoteChatEvent_AssistantMessage value)  assistantMessage,required TResult Function( AiRemoteChatEvent_ToolStarted value)  toolStarted,required TResult Function( AiRemoteChatEvent_ToolFinished value)  toolFinished,required TResult Function( AiRemoteChatEvent_DraftReady value)  draftReady,required TResult Function( AiRemoteChatEvent_TurnDone value)  turnDone,required TResult Function( AiRemoteChatEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case AiRemoteChatEvent_UserMessage():
return userMessage(_that);case AiRemoteChatEvent_Typing():
return typing(_that);case AiRemoteChatEvent_AssistantMessage():
return assistantMessage(_that);case AiRemoteChatEvent_ToolStarted():
return toolStarted(_that);case AiRemoteChatEvent_ToolFinished():
return toolFinished(_that);case AiRemoteChatEvent_DraftReady():
return draftReady(_that);case AiRemoteChatEvent_TurnDone():
return turnDone(_that);case AiRemoteChatEvent_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AiRemoteChatEvent_UserMessage value)?  userMessage,TResult? Function( AiRemoteChatEvent_Typing value)?  typing,TResult? Function( AiRemoteChatEvent_AssistantMessage value)?  assistantMessage,TResult? Function( AiRemoteChatEvent_ToolStarted value)?  toolStarted,TResult? Function( AiRemoteChatEvent_ToolFinished value)?  toolFinished,TResult? Function( AiRemoteChatEvent_DraftReady value)?  draftReady,TResult? Function( AiRemoteChatEvent_TurnDone value)?  turnDone,TResult? Function( AiRemoteChatEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case AiRemoteChatEvent_UserMessage() when userMessage != null:
return userMessage(_that);case AiRemoteChatEvent_Typing() when typing != null:
return typing(_that);case AiRemoteChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that);case AiRemoteChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that);case AiRemoteChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that);case AiRemoteChatEvent_DraftReady() when draftReady != null:
return draftReady(_that);case AiRemoteChatEvent_TurnDone() when turnDone != null:
return turnDone(_that);case AiRemoteChatEvent_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  userMessage,TResult Function()?  typing,TResult Function( String text)?  assistantMessage,TResult Function( String name,  String summary)?  toolStarted,TResult Function( String name,  bool ok,  String summary)?  toolFinished,TResult Function( AiRemoteDraft draft)?  draftReady,TResult Function()?  turnDone,TResult Function( String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AiRemoteChatEvent_UserMessage() when userMessage != null:
return userMessage(_that.text);case AiRemoteChatEvent_Typing() when typing != null:
return typing();case AiRemoteChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that.text);case AiRemoteChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that.name,_that.summary);case AiRemoteChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that.name,_that.ok,_that.summary);case AiRemoteChatEvent_DraftReady() when draftReady != null:
return draftReady(_that.draft);case AiRemoteChatEvent_TurnDone() when turnDone != null:
return turnDone();case AiRemoteChatEvent_Failed() when failed != null:
return failed(_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  userMessage,required TResult Function()  typing,required TResult Function( String text)  assistantMessage,required TResult Function( String name,  String summary)  toolStarted,required TResult Function( String name,  bool ok,  String summary)  toolFinished,required TResult Function( AiRemoteDraft draft)  draftReady,required TResult Function()  turnDone,required TResult Function( String detail)  failed,}) {final _that = this;
switch (_that) {
case AiRemoteChatEvent_UserMessage():
return userMessage(_that.text);case AiRemoteChatEvent_Typing():
return typing();case AiRemoteChatEvent_AssistantMessage():
return assistantMessage(_that.text);case AiRemoteChatEvent_ToolStarted():
return toolStarted(_that.name,_that.summary);case AiRemoteChatEvent_ToolFinished():
return toolFinished(_that.name,_that.ok,_that.summary);case AiRemoteChatEvent_DraftReady():
return draftReady(_that.draft);case AiRemoteChatEvent_TurnDone():
return turnDone();case AiRemoteChatEvent_Failed():
return failed(_that.detail);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  userMessage,TResult? Function()?  typing,TResult? Function( String text)?  assistantMessage,TResult? Function( String name,  String summary)?  toolStarted,TResult? Function( String name,  bool ok,  String summary)?  toolFinished,TResult? Function( AiRemoteDraft draft)?  draftReady,TResult? Function()?  turnDone,TResult? Function( String detail)?  failed,}) {final _that = this;
switch (_that) {
case AiRemoteChatEvent_UserMessage() when userMessage != null:
return userMessage(_that.text);case AiRemoteChatEvent_Typing() when typing != null:
return typing();case AiRemoteChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that.text);case AiRemoteChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that.name,_that.summary);case AiRemoteChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that.name,_that.ok,_that.summary);case AiRemoteChatEvent_DraftReady() when draftReady != null:
return draftReady(_that.draft);case AiRemoteChatEvent_TurnDone() when turnDone != null:
return turnDone();case AiRemoteChatEvent_Failed() when failed != null:
return failed(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class AiRemoteChatEvent_UserMessage extends AiRemoteChatEvent {
  const AiRemoteChatEvent_UserMessage({required this.text}): super._();
  

 final  String text;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiRemoteChatEvent_UserMessageCopyWith<AiRemoteChatEvent_UserMessage> get copyWith => _$AiRemoteChatEvent_UserMessageCopyWithImpl<AiRemoteChatEvent_UserMessage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_UserMessage&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'AiRemoteChatEvent.userMessage(text: $text)';
}


}

/// @nodoc
abstract mixin class $AiRemoteChatEvent_UserMessageCopyWith<$Res> implements $AiRemoteChatEventCopyWith<$Res> {
  factory $AiRemoteChatEvent_UserMessageCopyWith(AiRemoteChatEvent_UserMessage value, $Res Function(AiRemoteChatEvent_UserMessage) _then) = _$AiRemoteChatEvent_UserMessageCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AiRemoteChatEvent_UserMessageCopyWithImpl<$Res>
    implements $AiRemoteChatEvent_UserMessageCopyWith<$Res> {
  _$AiRemoteChatEvent_UserMessageCopyWithImpl(this._self, this._then);

  final AiRemoteChatEvent_UserMessage _self;
  final $Res Function(AiRemoteChatEvent_UserMessage) _then;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AiRemoteChatEvent_UserMessage(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiRemoteChatEvent_Typing extends AiRemoteChatEvent {
  const AiRemoteChatEvent_Typing(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_Typing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiRemoteChatEvent.typing()';
}


}




/// @nodoc


class AiRemoteChatEvent_AssistantMessage extends AiRemoteChatEvent {
  const AiRemoteChatEvent_AssistantMessage({required this.text}): super._();
  

 final  String text;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiRemoteChatEvent_AssistantMessageCopyWith<AiRemoteChatEvent_AssistantMessage> get copyWith => _$AiRemoteChatEvent_AssistantMessageCopyWithImpl<AiRemoteChatEvent_AssistantMessage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_AssistantMessage&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'AiRemoteChatEvent.assistantMessage(text: $text)';
}


}

/// @nodoc
abstract mixin class $AiRemoteChatEvent_AssistantMessageCopyWith<$Res> implements $AiRemoteChatEventCopyWith<$Res> {
  factory $AiRemoteChatEvent_AssistantMessageCopyWith(AiRemoteChatEvent_AssistantMessage value, $Res Function(AiRemoteChatEvent_AssistantMessage) _then) = _$AiRemoteChatEvent_AssistantMessageCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AiRemoteChatEvent_AssistantMessageCopyWithImpl<$Res>
    implements $AiRemoteChatEvent_AssistantMessageCopyWith<$Res> {
  _$AiRemoteChatEvent_AssistantMessageCopyWithImpl(this._self, this._then);

  final AiRemoteChatEvent_AssistantMessage _self;
  final $Res Function(AiRemoteChatEvent_AssistantMessage) _then;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AiRemoteChatEvent_AssistantMessage(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiRemoteChatEvent_ToolStarted extends AiRemoteChatEvent {
  const AiRemoteChatEvent_ToolStarted({required this.name, required this.summary}): super._();
  

 final  String name;
 final  String summary;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiRemoteChatEvent_ToolStartedCopyWith<AiRemoteChatEvent_ToolStarted> get copyWith => _$AiRemoteChatEvent_ToolStartedCopyWithImpl<AiRemoteChatEvent_ToolStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_ToolStarted&&(identical(other.name, name) || other.name == name)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode => Object.hash(runtimeType,name,summary);

@override
String toString() {
  return 'AiRemoteChatEvent.toolStarted(name: $name, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $AiRemoteChatEvent_ToolStartedCopyWith<$Res> implements $AiRemoteChatEventCopyWith<$Res> {
  factory $AiRemoteChatEvent_ToolStartedCopyWith(AiRemoteChatEvent_ToolStarted value, $Res Function(AiRemoteChatEvent_ToolStarted) _then) = _$AiRemoteChatEvent_ToolStartedCopyWithImpl;
@useResult
$Res call({
 String name, String summary
});




}
/// @nodoc
class _$AiRemoteChatEvent_ToolStartedCopyWithImpl<$Res>
    implements $AiRemoteChatEvent_ToolStartedCopyWith<$Res> {
  _$AiRemoteChatEvent_ToolStartedCopyWithImpl(this._self, this._then);

  final AiRemoteChatEvent_ToolStarted _self;
  final $Res Function(AiRemoteChatEvent_ToolStarted) _then;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? summary = null,}) {
  return _then(AiRemoteChatEvent_ToolStarted(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiRemoteChatEvent_ToolFinished extends AiRemoteChatEvent {
  const AiRemoteChatEvent_ToolFinished({required this.name, required this.ok, required this.summary}): super._();
  

 final  String name;
 final  bool ok;
 final  String summary;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiRemoteChatEvent_ToolFinishedCopyWith<AiRemoteChatEvent_ToolFinished> get copyWith => _$AiRemoteChatEvent_ToolFinishedCopyWithImpl<AiRemoteChatEvent_ToolFinished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_ToolFinished&&(identical(other.name, name) || other.name == name)&&(identical(other.ok, ok) || other.ok == ok)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode => Object.hash(runtimeType,name,ok,summary);

@override
String toString() {
  return 'AiRemoteChatEvent.toolFinished(name: $name, ok: $ok, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $AiRemoteChatEvent_ToolFinishedCopyWith<$Res> implements $AiRemoteChatEventCopyWith<$Res> {
  factory $AiRemoteChatEvent_ToolFinishedCopyWith(AiRemoteChatEvent_ToolFinished value, $Res Function(AiRemoteChatEvent_ToolFinished) _then) = _$AiRemoteChatEvent_ToolFinishedCopyWithImpl;
@useResult
$Res call({
 String name, bool ok, String summary
});




}
/// @nodoc
class _$AiRemoteChatEvent_ToolFinishedCopyWithImpl<$Res>
    implements $AiRemoteChatEvent_ToolFinishedCopyWith<$Res> {
  _$AiRemoteChatEvent_ToolFinishedCopyWithImpl(this._self, this._then);

  final AiRemoteChatEvent_ToolFinished _self;
  final $Res Function(AiRemoteChatEvent_ToolFinished) _then;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? ok = null,Object? summary = null,}) {
  return _then(AiRemoteChatEvent_ToolFinished(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiRemoteChatEvent_DraftReady extends AiRemoteChatEvent {
  const AiRemoteChatEvent_DraftReady({required this.draft}): super._();
  

 final  AiRemoteDraft draft;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiRemoteChatEvent_DraftReadyCopyWith<AiRemoteChatEvent_DraftReady> get copyWith => _$AiRemoteChatEvent_DraftReadyCopyWithImpl<AiRemoteChatEvent_DraftReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_DraftReady&&(identical(other.draft, draft) || other.draft == draft));
}


@override
int get hashCode => Object.hash(runtimeType,draft);

@override
String toString() {
  return 'AiRemoteChatEvent.draftReady(draft: $draft)';
}


}

/// @nodoc
abstract mixin class $AiRemoteChatEvent_DraftReadyCopyWith<$Res> implements $AiRemoteChatEventCopyWith<$Res> {
  factory $AiRemoteChatEvent_DraftReadyCopyWith(AiRemoteChatEvent_DraftReady value, $Res Function(AiRemoteChatEvent_DraftReady) _then) = _$AiRemoteChatEvent_DraftReadyCopyWithImpl;
@useResult
$Res call({
 AiRemoteDraft draft
});




}
/// @nodoc
class _$AiRemoteChatEvent_DraftReadyCopyWithImpl<$Res>
    implements $AiRemoteChatEvent_DraftReadyCopyWith<$Res> {
  _$AiRemoteChatEvent_DraftReadyCopyWithImpl(this._self, this._then);

  final AiRemoteChatEvent_DraftReady _self;
  final $Res Function(AiRemoteChatEvent_DraftReady) _then;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? draft = null,}) {
  return _then(AiRemoteChatEvent_DraftReady(
draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as AiRemoteDraft,
  ));
}


}

/// @nodoc


class AiRemoteChatEvent_TurnDone extends AiRemoteChatEvent {
  const AiRemoteChatEvent_TurnDone(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_TurnDone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiRemoteChatEvent.turnDone()';
}


}




/// @nodoc


class AiRemoteChatEvent_Failed extends AiRemoteChatEvent {
  const AiRemoteChatEvent_Failed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiRemoteChatEvent_FailedCopyWith<AiRemoteChatEvent_Failed> get copyWith => _$AiRemoteChatEvent_FailedCopyWithImpl<AiRemoteChatEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiRemoteChatEvent_Failed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'AiRemoteChatEvent.failed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $AiRemoteChatEvent_FailedCopyWith<$Res> implements $AiRemoteChatEventCopyWith<$Res> {
  factory $AiRemoteChatEvent_FailedCopyWith(AiRemoteChatEvent_Failed value, $Res Function(AiRemoteChatEvent_Failed) _then) = _$AiRemoteChatEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$AiRemoteChatEvent_FailedCopyWithImpl<$Res>
    implements $AiRemoteChatEvent_FailedCopyWith<$Res> {
  _$AiRemoteChatEvent_FailedCopyWithImpl(this._self, this._then);

  final AiRemoteChatEvent_Failed _self;
  final $Res Function(AiRemoteChatEvent_Failed) _then;

/// Create a copy of AiRemoteChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(AiRemoteChatEvent_Failed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ConnectionEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionEvent()';
}


}

/// @nodoc
class $ConnectionEventCopyWith<$Res>  {
$ConnectionEventCopyWith(ConnectionEvent _, $Res Function(ConnectionEvent) __);
}


/// Adds pattern-matching-related methods to [ConnectionEvent].
extension ConnectionEventPatterns on ConnectionEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConnectionEvent_DeviceConnected value)?  deviceConnected,TResult Function( ConnectionEvent_DeviceDisconnected value)?  deviceDisconnected,TResult Function( ConnectionEvent_ActionExecutionRequested value)?  actionExecutionRequested,TResult Function( ConnectionEvent_AiMessageRequested value)?  aiMessageRequested,TResult Function( ConnectionEvent_AiActivateRequested value)?  aiActivateRequested,TResult Function( ConnectionEvent_AiApplyDraftRequested value)?  aiApplyDraftRequested,TResult Function( ConnectionEvent_AiRunDraftRequested value)?  aiRunDraftRequested,TResult Function( ConnectionEvent_AiAskAboutProcessRequested value)?  aiAskAboutProcessRequested,TResult Function( ConnectionEvent_Connected value)?  connected,TResult Function( ConnectionEvent_Disconnected value)?  disconnected,TResult Function( ConnectionEvent_HardwareSnapshotReceived value)?  hardwareSnapshotReceived,TResult Function( ConnectionEvent_ActionsCatalogReceived value)?  actionsCatalogReceived,TResult Function( ConnectionEvent_ActionAckReceived value)?  actionAckReceived,TResult Function( ConnectionEvent_RelayOfferReceived value)?  relayOfferReceived,TResult Function( ConnectionEvent_TopProcessesReceived value)?  topProcessesReceived,TResult Function( ConnectionEvent_ProcessTerminatedReceived value)?  processTerminatedReceived,TResult Function( ConnectionEvent_ActionRunUpdateReceived value)?  actionRunUpdateReceived,TResult Function( ConnectionEvent_HubSubscriptionsSnapshotReceived value)?  hubSubscriptionsSnapshotReceived,TResult Function( ConnectionEvent_HostComponentsReceived value)?  hostComponentsReceived,TResult Function( ConnectionEvent_AiStatusReceived value)?  aiStatusReceived,TResult Function( ConnectionEvent_AiChatEventReceived value)?  aiChatEventReceived,TResult Function( ConnectionEvent_NotesResponseReceived value)?  notesResponseReceived,TResult Function( ConnectionEvent_NotesChanged value)?  notesChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConnectionEvent_DeviceConnected() when deviceConnected != null:
return deviceConnected(_that);case ConnectionEvent_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that);case ConnectionEvent_ActionExecutionRequested() when actionExecutionRequested != null:
return actionExecutionRequested(_that);case ConnectionEvent_AiMessageRequested() when aiMessageRequested != null:
return aiMessageRequested(_that);case ConnectionEvent_AiActivateRequested() when aiActivateRequested != null:
return aiActivateRequested(_that);case ConnectionEvent_AiApplyDraftRequested() when aiApplyDraftRequested != null:
return aiApplyDraftRequested(_that);case ConnectionEvent_AiRunDraftRequested() when aiRunDraftRequested != null:
return aiRunDraftRequested(_that);case ConnectionEvent_AiAskAboutProcessRequested() when aiAskAboutProcessRequested != null:
return aiAskAboutProcessRequested(_that);case ConnectionEvent_Connected() when connected != null:
return connected(_that);case ConnectionEvent_Disconnected() when disconnected != null:
return disconnected(_that);case ConnectionEvent_HardwareSnapshotReceived() when hardwareSnapshotReceived != null:
return hardwareSnapshotReceived(_that);case ConnectionEvent_ActionsCatalogReceived() when actionsCatalogReceived != null:
return actionsCatalogReceived(_that);case ConnectionEvent_ActionAckReceived() when actionAckReceived != null:
return actionAckReceived(_that);case ConnectionEvent_RelayOfferReceived() when relayOfferReceived != null:
return relayOfferReceived(_that);case ConnectionEvent_TopProcessesReceived() when topProcessesReceived != null:
return topProcessesReceived(_that);case ConnectionEvent_ProcessTerminatedReceived() when processTerminatedReceived != null:
return processTerminatedReceived(_that);case ConnectionEvent_ActionRunUpdateReceived() when actionRunUpdateReceived != null:
return actionRunUpdateReceived(_that);case ConnectionEvent_HubSubscriptionsSnapshotReceived() when hubSubscriptionsSnapshotReceived != null:
return hubSubscriptionsSnapshotReceived(_that);case ConnectionEvent_HostComponentsReceived() when hostComponentsReceived != null:
return hostComponentsReceived(_that);case ConnectionEvent_AiStatusReceived() when aiStatusReceived != null:
return aiStatusReceived(_that);case ConnectionEvent_AiChatEventReceived() when aiChatEventReceived != null:
return aiChatEventReceived(_that);case ConnectionEvent_NotesResponseReceived() when notesResponseReceived != null:
return notesResponseReceived(_that);case ConnectionEvent_NotesChanged() when notesChanged != null:
return notesChanged(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConnectionEvent_DeviceConnected value)  deviceConnected,required TResult Function( ConnectionEvent_DeviceDisconnected value)  deviceDisconnected,required TResult Function( ConnectionEvent_ActionExecutionRequested value)  actionExecutionRequested,required TResult Function( ConnectionEvent_AiMessageRequested value)  aiMessageRequested,required TResult Function( ConnectionEvent_AiActivateRequested value)  aiActivateRequested,required TResult Function( ConnectionEvent_AiApplyDraftRequested value)  aiApplyDraftRequested,required TResult Function( ConnectionEvent_AiRunDraftRequested value)  aiRunDraftRequested,required TResult Function( ConnectionEvent_AiAskAboutProcessRequested value)  aiAskAboutProcessRequested,required TResult Function( ConnectionEvent_Connected value)  connected,required TResult Function( ConnectionEvent_Disconnected value)  disconnected,required TResult Function( ConnectionEvent_HardwareSnapshotReceived value)  hardwareSnapshotReceived,required TResult Function( ConnectionEvent_ActionsCatalogReceived value)  actionsCatalogReceived,required TResult Function( ConnectionEvent_ActionAckReceived value)  actionAckReceived,required TResult Function( ConnectionEvent_RelayOfferReceived value)  relayOfferReceived,required TResult Function( ConnectionEvent_TopProcessesReceived value)  topProcessesReceived,required TResult Function( ConnectionEvent_ProcessTerminatedReceived value)  processTerminatedReceived,required TResult Function( ConnectionEvent_ActionRunUpdateReceived value)  actionRunUpdateReceived,required TResult Function( ConnectionEvent_HubSubscriptionsSnapshotReceived value)  hubSubscriptionsSnapshotReceived,required TResult Function( ConnectionEvent_HostComponentsReceived value)  hostComponentsReceived,required TResult Function( ConnectionEvent_AiStatusReceived value)  aiStatusReceived,required TResult Function( ConnectionEvent_AiChatEventReceived value)  aiChatEventReceived,required TResult Function( ConnectionEvent_NotesResponseReceived value)  notesResponseReceived,required TResult Function( ConnectionEvent_NotesChanged value)  notesChanged,}){
final _that = this;
switch (_that) {
case ConnectionEvent_DeviceConnected():
return deviceConnected(_that);case ConnectionEvent_DeviceDisconnected():
return deviceDisconnected(_that);case ConnectionEvent_ActionExecutionRequested():
return actionExecutionRequested(_that);case ConnectionEvent_AiMessageRequested():
return aiMessageRequested(_that);case ConnectionEvent_AiActivateRequested():
return aiActivateRequested(_that);case ConnectionEvent_AiApplyDraftRequested():
return aiApplyDraftRequested(_that);case ConnectionEvent_AiRunDraftRequested():
return aiRunDraftRequested(_that);case ConnectionEvent_AiAskAboutProcessRequested():
return aiAskAboutProcessRequested(_that);case ConnectionEvent_Connected():
return connected(_that);case ConnectionEvent_Disconnected():
return disconnected(_that);case ConnectionEvent_HardwareSnapshotReceived():
return hardwareSnapshotReceived(_that);case ConnectionEvent_ActionsCatalogReceived():
return actionsCatalogReceived(_that);case ConnectionEvent_ActionAckReceived():
return actionAckReceived(_that);case ConnectionEvent_RelayOfferReceived():
return relayOfferReceived(_that);case ConnectionEvent_TopProcessesReceived():
return topProcessesReceived(_that);case ConnectionEvent_ProcessTerminatedReceived():
return processTerminatedReceived(_that);case ConnectionEvent_ActionRunUpdateReceived():
return actionRunUpdateReceived(_that);case ConnectionEvent_HubSubscriptionsSnapshotReceived():
return hubSubscriptionsSnapshotReceived(_that);case ConnectionEvent_HostComponentsReceived():
return hostComponentsReceived(_that);case ConnectionEvent_AiStatusReceived():
return aiStatusReceived(_that);case ConnectionEvent_AiChatEventReceived():
return aiChatEventReceived(_that);case ConnectionEvent_NotesResponseReceived():
return notesResponseReceived(_that);case ConnectionEvent_NotesChanged():
return notesChanged(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConnectionEvent_DeviceConnected value)?  deviceConnected,TResult? Function( ConnectionEvent_DeviceDisconnected value)?  deviceDisconnected,TResult? Function( ConnectionEvent_ActionExecutionRequested value)?  actionExecutionRequested,TResult? Function( ConnectionEvent_AiMessageRequested value)?  aiMessageRequested,TResult? Function( ConnectionEvent_AiActivateRequested value)?  aiActivateRequested,TResult? Function( ConnectionEvent_AiApplyDraftRequested value)?  aiApplyDraftRequested,TResult? Function( ConnectionEvent_AiRunDraftRequested value)?  aiRunDraftRequested,TResult? Function( ConnectionEvent_AiAskAboutProcessRequested value)?  aiAskAboutProcessRequested,TResult? Function( ConnectionEvent_Connected value)?  connected,TResult? Function( ConnectionEvent_Disconnected value)?  disconnected,TResult? Function( ConnectionEvent_HardwareSnapshotReceived value)?  hardwareSnapshotReceived,TResult? Function( ConnectionEvent_ActionsCatalogReceived value)?  actionsCatalogReceived,TResult? Function( ConnectionEvent_ActionAckReceived value)?  actionAckReceived,TResult? Function( ConnectionEvent_RelayOfferReceived value)?  relayOfferReceived,TResult? Function( ConnectionEvent_TopProcessesReceived value)?  topProcessesReceived,TResult? Function( ConnectionEvent_ProcessTerminatedReceived value)?  processTerminatedReceived,TResult? Function( ConnectionEvent_ActionRunUpdateReceived value)?  actionRunUpdateReceived,TResult? Function( ConnectionEvent_HubSubscriptionsSnapshotReceived value)?  hubSubscriptionsSnapshotReceived,TResult? Function( ConnectionEvent_HostComponentsReceived value)?  hostComponentsReceived,TResult? Function( ConnectionEvent_AiStatusReceived value)?  aiStatusReceived,TResult? Function( ConnectionEvent_AiChatEventReceived value)?  aiChatEventReceived,TResult? Function( ConnectionEvent_NotesResponseReceived value)?  notesResponseReceived,TResult? Function( ConnectionEvent_NotesChanged value)?  notesChanged,}){
final _that = this;
switch (_that) {
case ConnectionEvent_DeviceConnected() when deviceConnected != null:
return deviceConnected(_that);case ConnectionEvent_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that);case ConnectionEvent_ActionExecutionRequested() when actionExecutionRequested != null:
return actionExecutionRequested(_that);case ConnectionEvent_AiMessageRequested() when aiMessageRequested != null:
return aiMessageRequested(_that);case ConnectionEvent_AiActivateRequested() when aiActivateRequested != null:
return aiActivateRequested(_that);case ConnectionEvent_AiApplyDraftRequested() when aiApplyDraftRequested != null:
return aiApplyDraftRequested(_that);case ConnectionEvent_AiRunDraftRequested() when aiRunDraftRequested != null:
return aiRunDraftRequested(_that);case ConnectionEvent_AiAskAboutProcessRequested() when aiAskAboutProcessRequested != null:
return aiAskAboutProcessRequested(_that);case ConnectionEvent_Connected() when connected != null:
return connected(_that);case ConnectionEvent_Disconnected() when disconnected != null:
return disconnected(_that);case ConnectionEvent_HardwareSnapshotReceived() when hardwareSnapshotReceived != null:
return hardwareSnapshotReceived(_that);case ConnectionEvent_ActionsCatalogReceived() when actionsCatalogReceived != null:
return actionsCatalogReceived(_that);case ConnectionEvent_ActionAckReceived() when actionAckReceived != null:
return actionAckReceived(_that);case ConnectionEvent_RelayOfferReceived() when relayOfferReceived != null:
return relayOfferReceived(_that);case ConnectionEvent_TopProcessesReceived() when topProcessesReceived != null:
return topProcessesReceived(_that);case ConnectionEvent_ProcessTerminatedReceived() when processTerminatedReceived != null:
return processTerminatedReceived(_that);case ConnectionEvent_ActionRunUpdateReceived() when actionRunUpdateReceived != null:
return actionRunUpdateReceived(_that);case ConnectionEvent_HubSubscriptionsSnapshotReceived() when hubSubscriptionsSnapshotReceived != null:
return hubSubscriptionsSnapshotReceived(_that);case ConnectionEvent_HostComponentsReceived() when hostComponentsReceived != null:
return hostComponentsReceived(_that);case ConnectionEvent_AiStatusReceived() when aiStatusReceived != null:
return aiStatusReceived(_that);case ConnectionEvent_AiChatEventReceived() when aiChatEventReceived != null:
return aiChatEventReceived(_that);case ConnectionEvent_NotesResponseReceived() when notesResponseReceived != null:
return notesResponseReceived(_that);case ConnectionEvent_NotesChanged() when notesChanged != null:
return notesChanged(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String deviceId)?  deviceConnected,TResult Function( String deviceId)?  deviceDisconnected,TResult Function( String deviceId,  String actionId,  List<ActionParamValue> params)?  actionExecutionRequested,TResult Function( String deviceId,  String text)?  aiMessageRequested,TResult Function( String deviceId)?  aiActivateRequested,TResult Function( String deviceId,  AiRemoteDraft draft)?  aiApplyDraftRequested,TResult Function( String deviceId,  AiRemoteDraft draft)?  aiRunDraftRequested,TResult Function( String deviceId,  ProcessGroup group)?  aiAskAboutProcessRequested,TResult Function()?  connected,TResult Function()?  disconnected,TResult Function( HardwareSnapshot field0)?  hardwareSnapshotReceived,TResult Function( List<RemoteAction> field0)?  actionsCatalogReceived,TResult Function( String actionId,  bool success,  String? error)?  actionAckReceived,TResult Function( String host,  int port,  String tokenHex)?  relayOfferReceived,TResult Function( TopProcesses field0)?  topProcessesReceived,TResult Function( String name,  int killed,  int failed,  String? rejectedReason)?  processTerminatedReceived,TResult Function( String runId,  String actionId,  RunPhase phase,  int? exitCode,  int elapsedMs,  String outputTail)?  actionRunUpdateReceived,TResult Function( List<HubSubscriptionSummary> field0)?  hubSubscriptionsSnapshotReceived,TResult Function( HostComponents field0)?  hostComponentsReceived,TResult Function( bool enabled,  bool ready)?  aiStatusReceived,TResult Function( AiRemoteChatEvent field0)?  aiChatEventReceived,TResult Function( String requestId,  NotesReply response)?  notesResponseReceived,TResult Function()?  notesChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConnectionEvent_DeviceConnected() when deviceConnected != null:
return deviceConnected(_that.deviceId);case ConnectionEvent_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that.deviceId);case ConnectionEvent_ActionExecutionRequested() when actionExecutionRequested != null:
return actionExecutionRequested(_that.deviceId,_that.actionId,_that.params);case ConnectionEvent_AiMessageRequested() when aiMessageRequested != null:
return aiMessageRequested(_that.deviceId,_that.text);case ConnectionEvent_AiActivateRequested() when aiActivateRequested != null:
return aiActivateRequested(_that.deviceId);case ConnectionEvent_AiApplyDraftRequested() when aiApplyDraftRequested != null:
return aiApplyDraftRequested(_that.deviceId,_that.draft);case ConnectionEvent_AiRunDraftRequested() when aiRunDraftRequested != null:
return aiRunDraftRequested(_that.deviceId,_that.draft);case ConnectionEvent_AiAskAboutProcessRequested() when aiAskAboutProcessRequested != null:
return aiAskAboutProcessRequested(_that.deviceId,_that.group);case ConnectionEvent_Connected() when connected != null:
return connected();case ConnectionEvent_Disconnected() when disconnected != null:
return disconnected();case ConnectionEvent_HardwareSnapshotReceived() when hardwareSnapshotReceived != null:
return hardwareSnapshotReceived(_that.field0);case ConnectionEvent_ActionsCatalogReceived() when actionsCatalogReceived != null:
return actionsCatalogReceived(_that.field0);case ConnectionEvent_ActionAckReceived() when actionAckReceived != null:
return actionAckReceived(_that.actionId,_that.success,_that.error);case ConnectionEvent_RelayOfferReceived() when relayOfferReceived != null:
return relayOfferReceived(_that.host,_that.port,_that.tokenHex);case ConnectionEvent_TopProcessesReceived() when topProcessesReceived != null:
return topProcessesReceived(_that.field0);case ConnectionEvent_ProcessTerminatedReceived() when processTerminatedReceived != null:
return processTerminatedReceived(_that.name,_that.killed,_that.failed,_that.rejectedReason);case ConnectionEvent_ActionRunUpdateReceived() when actionRunUpdateReceived != null:
return actionRunUpdateReceived(_that.runId,_that.actionId,_that.phase,_that.exitCode,_that.elapsedMs,_that.outputTail);case ConnectionEvent_HubSubscriptionsSnapshotReceived() when hubSubscriptionsSnapshotReceived != null:
return hubSubscriptionsSnapshotReceived(_that.field0);case ConnectionEvent_HostComponentsReceived() when hostComponentsReceived != null:
return hostComponentsReceived(_that.field0);case ConnectionEvent_AiStatusReceived() when aiStatusReceived != null:
return aiStatusReceived(_that.enabled,_that.ready);case ConnectionEvent_AiChatEventReceived() when aiChatEventReceived != null:
return aiChatEventReceived(_that.field0);case ConnectionEvent_NotesResponseReceived() when notesResponseReceived != null:
return notesResponseReceived(_that.requestId,_that.response);case ConnectionEvent_NotesChanged() when notesChanged != null:
return notesChanged();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String deviceId)  deviceConnected,required TResult Function( String deviceId)  deviceDisconnected,required TResult Function( String deviceId,  String actionId,  List<ActionParamValue> params)  actionExecutionRequested,required TResult Function( String deviceId,  String text)  aiMessageRequested,required TResult Function( String deviceId)  aiActivateRequested,required TResult Function( String deviceId,  AiRemoteDraft draft)  aiApplyDraftRequested,required TResult Function( String deviceId,  AiRemoteDraft draft)  aiRunDraftRequested,required TResult Function( String deviceId,  ProcessGroup group)  aiAskAboutProcessRequested,required TResult Function()  connected,required TResult Function()  disconnected,required TResult Function( HardwareSnapshot field0)  hardwareSnapshotReceived,required TResult Function( List<RemoteAction> field0)  actionsCatalogReceived,required TResult Function( String actionId,  bool success,  String? error)  actionAckReceived,required TResult Function( String host,  int port,  String tokenHex)  relayOfferReceived,required TResult Function( TopProcesses field0)  topProcessesReceived,required TResult Function( String name,  int killed,  int failed,  String? rejectedReason)  processTerminatedReceived,required TResult Function( String runId,  String actionId,  RunPhase phase,  int? exitCode,  int elapsedMs,  String outputTail)  actionRunUpdateReceived,required TResult Function( List<HubSubscriptionSummary> field0)  hubSubscriptionsSnapshotReceived,required TResult Function( HostComponents field0)  hostComponentsReceived,required TResult Function( bool enabled,  bool ready)  aiStatusReceived,required TResult Function( AiRemoteChatEvent field0)  aiChatEventReceived,required TResult Function( String requestId,  NotesReply response)  notesResponseReceived,required TResult Function()  notesChanged,}) {final _that = this;
switch (_that) {
case ConnectionEvent_DeviceConnected():
return deviceConnected(_that.deviceId);case ConnectionEvent_DeviceDisconnected():
return deviceDisconnected(_that.deviceId);case ConnectionEvent_ActionExecutionRequested():
return actionExecutionRequested(_that.deviceId,_that.actionId,_that.params);case ConnectionEvent_AiMessageRequested():
return aiMessageRequested(_that.deviceId,_that.text);case ConnectionEvent_AiActivateRequested():
return aiActivateRequested(_that.deviceId);case ConnectionEvent_AiApplyDraftRequested():
return aiApplyDraftRequested(_that.deviceId,_that.draft);case ConnectionEvent_AiRunDraftRequested():
return aiRunDraftRequested(_that.deviceId,_that.draft);case ConnectionEvent_AiAskAboutProcessRequested():
return aiAskAboutProcessRequested(_that.deviceId,_that.group);case ConnectionEvent_Connected():
return connected();case ConnectionEvent_Disconnected():
return disconnected();case ConnectionEvent_HardwareSnapshotReceived():
return hardwareSnapshotReceived(_that.field0);case ConnectionEvent_ActionsCatalogReceived():
return actionsCatalogReceived(_that.field0);case ConnectionEvent_ActionAckReceived():
return actionAckReceived(_that.actionId,_that.success,_that.error);case ConnectionEvent_RelayOfferReceived():
return relayOfferReceived(_that.host,_that.port,_that.tokenHex);case ConnectionEvent_TopProcessesReceived():
return topProcessesReceived(_that.field0);case ConnectionEvent_ProcessTerminatedReceived():
return processTerminatedReceived(_that.name,_that.killed,_that.failed,_that.rejectedReason);case ConnectionEvent_ActionRunUpdateReceived():
return actionRunUpdateReceived(_that.runId,_that.actionId,_that.phase,_that.exitCode,_that.elapsedMs,_that.outputTail);case ConnectionEvent_HubSubscriptionsSnapshotReceived():
return hubSubscriptionsSnapshotReceived(_that.field0);case ConnectionEvent_HostComponentsReceived():
return hostComponentsReceived(_that.field0);case ConnectionEvent_AiStatusReceived():
return aiStatusReceived(_that.enabled,_that.ready);case ConnectionEvent_AiChatEventReceived():
return aiChatEventReceived(_that.field0);case ConnectionEvent_NotesResponseReceived():
return notesResponseReceived(_that.requestId,_that.response);case ConnectionEvent_NotesChanged():
return notesChanged();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String deviceId)?  deviceConnected,TResult? Function( String deviceId)?  deviceDisconnected,TResult? Function( String deviceId,  String actionId,  List<ActionParamValue> params)?  actionExecutionRequested,TResult? Function( String deviceId,  String text)?  aiMessageRequested,TResult? Function( String deviceId)?  aiActivateRequested,TResult? Function( String deviceId,  AiRemoteDraft draft)?  aiApplyDraftRequested,TResult? Function( String deviceId,  AiRemoteDraft draft)?  aiRunDraftRequested,TResult? Function( String deviceId,  ProcessGroup group)?  aiAskAboutProcessRequested,TResult? Function()?  connected,TResult? Function()?  disconnected,TResult? Function( HardwareSnapshot field0)?  hardwareSnapshotReceived,TResult? Function( List<RemoteAction> field0)?  actionsCatalogReceived,TResult? Function( String actionId,  bool success,  String? error)?  actionAckReceived,TResult? Function( String host,  int port,  String tokenHex)?  relayOfferReceived,TResult? Function( TopProcesses field0)?  topProcessesReceived,TResult? Function( String name,  int killed,  int failed,  String? rejectedReason)?  processTerminatedReceived,TResult? Function( String runId,  String actionId,  RunPhase phase,  int? exitCode,  int elapsedMs,  String outputTail)?  actionRunUpdateReceived,TResult? Function( List<HubSubscriptionSummary> field0)?  hubSubscriptionsSnapshotReceived,TResult? Function( HostComponents field0)?  hostComponentsReceived,TResult? Function( bool enabled,  bool ready)?  aiStatusReceived,TResult? Function( AiRemoteChatEvent field0)?  aiChatEventReceived,TResult? Function( String requestId,  NotesReply response)?  notesResponseReceived,TResult? Function()?  notesChanged,}) {final _that = this;
switch (_that) {
case ConnectionEvent_DeviceConnected() when deviceConnected != null:
return deviceConnected(_that.deviceId);case ConnectionEvent_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that.deviceId);case ConnectionEvent_ActionExecutionRequested() when actionExecutionRequested != null:
return actionExecutionRequested(_that.deviceId,_that.actionId,_that.params);case ConnectionEvent_AiMessageRequested() when aiMessageRequested != null:
return aiMessageRequested(_that.deviceId,_that.text);case ConnectionEvent_AiActivateRequested() when aiActivateRequested != null:
return aiActivateRequested(_that.deviceId);case ConnectionEvent_AiApplyDraftRequested() when aiApplyDraftRequested != null:
return aiApplyDraftRequested(_that.deviceId,_that.draft);case ConnectionEvent_AiRunDraftRequested() when aiRunDraftRequested != null:
return aiRunDraftRequested(_that.deviceId,_that.draft);case ConnectionEvent_AiAskAboutProcessRequested() when aiAskAboutProcessRequested != null:
return aiAskAboutProcessRequested(_that.deviceId,_that.group);case ConnectionEvent_Connected() when connected != null:
return connected();case ConnectionEvent_Disconnected() when disconnected != null:
return disconnected();case ConnectionEvent_HardwareSnapshotReceived() when hardwareSnapshotReceived != null:
return hardwareSnapshotReceived(_that.field0);case ConnectionEvent_ActionsCatalogReceived() when actionsCatalogReceived != null:
return actionsCatalogReceived(_that.field0);case ConnectionEvent_ActionAckReceived() when actionAckReceived != null:
return actionAckReceived(_that.actionId,_that.success,_that.error);case ConnectionEvent_RelayOfferReceived() when relayOfferReceived != null:
return relayOfferReceived(_that.host,_that.port,_that.tokenHex);case ConnectionEvent_TopProcessesReceived() when topProcessesReceived != null:
return topProcessesReceived(_that.field0);case ConnectionEvent_ProcessTerminatedReceived() when processTerminatedReceived != null:
return processTerminatedReceived(_that.name,_that.killed,_that.failed,_that.rejectedReason);case ConnectionEvent_ActionRunUpdateReceived() when actionRunUpdateReceived != null:
return actionRunUpdateReceived(_that.runId,_that.actionId,_that.phase,_that.exitCode,_that.elapsedMs,_that.outputTail);case ConnectionEvent_HubSubscriptionsSnapshotReceived() when hubSubscriptionsSnapshotReceived != null:
return hubSubscriptionsSnapshotReceived(_that.field0);case ConnectionEvent_HostComponentsReceived() when hostComponentsReceived != null:
return hostComponentsReceived(_that.field0);case ConnectionEvent_AiStatusReceived() when aiStatusReceived != null:
return aiStatusReceived(_that.enabled,_that.ready);case ConnectionEvent_AiChatEventReceived() when aiChatEventReceived != null:
return aiChatEventReceived(_that.field0);case ConnectionEvent_NotesResponseReceived() when notesResponseReceived != null:
return notesResponseReceived(_that.requestId,_that.response);case ConnectionEvent_NotesChanged() when notesChanged != null:
return notesChanged();case _:
  return null;

}
}

}

/// @nodoc


class ConnectionEvent_DeviceConnected extends ConnectionEvent {
  const ConnectionEvent_DeviceConnected({required this.deviceId}): super._();
  

 final  String deviceId;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_DeviceConnectedCopyWith<ConnectionEvent_DeviceConnected> get copyWith => _$ConnectionEvent_DeviceConnectedCopyWithImpl<ConnectionEvent_DeviceConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_DeviceConnected&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId);

@override
String toString() {
  return 'ConnectionEvent.deviceConnected(deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_DeviceConnectedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_DeviceConnectedCopyWith(ConnectionEvent_DeviceConnected value, $Res Function(ConnectionEvent_DeviceConnected) _then) = _$ConnectionEvent_DeviceConnectedCopyWithImpl;
@useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$ConnectionEvent_DeviceConnectedCopyWithImpl<$Res>
    implements $ConnectionEvent_DeviceConnectedCopyWith<$Res> {
  _$ConnectionEvent_DeviceConnectedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_DeviceConnected _self;
  final $Res Function(ConnectionEvent_DeviceConnected) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,}) {
  return _then(ConnectionEvent_DeviceConnected(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectionEvent_DeviceDisconnected extends ConnectionEvent {
  const ConnectionEvent_DeviceDisconnected({required this.deviceId}): super._();
  

 final  String deviceId;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_DeviceDisconnectedCopyWith<ConnectionEvent_DeviceDisconnected> get copyWith => _$ConnectionEvent_DeviceDisconnectedCopyWithImpl<ConnectionEvent_DeviceDisconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_DeviceDisconnected&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId);

@override
String toString() {
  return 'ConnectionEvent.deviceDisconnected(deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_DeviceDisconnectedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_DeviceDisconnectedCopyWith(ConnectionEvent_DeviceDisconnected value, $Res Function(ConnectionEvent_DeviceDisconnected) _then) = _$ConnectionEvent_DeviceDisconnectedCopyWithImpl;
@useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$ConnectionEvent_DeviceDisconnectedCopyWithImpl<$Res>
    implements $ConnectionEvent_DeviceDisconnectedCopyWith<$Res> {
  _$ConnectionEvent_DeviceDisconnectedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_DeviceDisconnected _self;
  final $Res Function(ConnectionEvent_DeviceDisconnected) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,}) {
  return _then(ConnectionEvent_DeviceDisconnected(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectionEvent_ActionExecutionRequested extends ConnectionEvent {
  const ConnectionEvent_ActionExecutionRequested({required this.deviceId, required this.actionId, required final  List<ActionParamValue> params}): _params = params,super._();
  

 final  String deviceId;
 final  String actionId;
/// Valores de los `{{placeholders}}` cargados en el dispositivo
/// remoto -- `main.dart` los pasa tal cual a `renderCommand`, asi
/// que la accion corre igual que disparada desde el deck local.
 final  List<ActionParamValue> _params;
/// Valores de los `{{placeholders}}` cargados en el dispositivo
/// remoto -- `main.dart` los pasa tal cual a `renderCommand`, asi
/// que la accion corre igual que disparada desde el deck local.
 List<ActionParamValue> get params {
  if (_params is EqualUnmodifiableListView) return _params;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_params);
}


/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_ActionExecutionRequestedCopyWith<ConnectionEvent_ActionExecutionRequested> get copyWith => _$ConnectionEvent_ActionExecutionRequestedCopyWithImpl<ConnectionEvent_ActionExecutionRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_ActionExecutionRequested&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.actionId, actionId) || other.actionId == actionId)&&const DeepCollectionEquality().equals(other._params, _params));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,actionId,const DeepCollectionEquality().hash(_params));

@override
String toString() {
  return 'ConnectionEvent.actionExecutionRequested(deviceId: $deviceId, actionId: $actionId, params: $params)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_ActionExecutionRequestedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_ActionExecutionRequestedCopyWith(ConnectionEvent_ActionExecutionRequested value, $Res Function(ConnectionEvent_ActionExecutionRequested) _then) = _$ConnectionEvent_ActionExecutionRequestedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String actionId, List<ActionParamValue> params
});




}
/// @nodoc
class _$ConnectionEvent_ActionExecutionRequestedCopyWithImpl<$Res>
    implements $ConnectionEvent_ActionExecutionRequestedCopyWith<$Res> {
  _$ConnectionEvent_ActionExecutionRequestedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_ActionExecutionRequested _self;
  final $Res Function(ConnectionEvent_ActionExecutionRequested) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? actionId = null,Object? params = null,}) {
  return _then(ConnectionEvent_ActionExecutionRequested(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,actionId: null == actionId ? _self.actionId : actionId // ignore: cast_nullable_to_non_nullable
as String,params: null == params ? _self._params : params // ignore: cast_nullable_to_non_nullable
as List<ActionParamValue>,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiMessageRequested extends ConnectionEvent {
  const ConnectionEvent_AiMessageRequested({required this.deviceId, required this.text}): super._();
  

 final  String deviceId;
 final  String text;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiMessageRequestedCopyWith<ConnectionEvent_AiMessageRequested> get copyWith => _$ConnectionEvent_AiMessageRequestedCopyWithImpl<ConnectionEvent_AiMessageRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiMessageRequested&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,text);

@override
String toString() {
  return 'ConnectionEvent.aiMessageRequested(deviceId: $deviceId, text: $text)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiMessageRequestedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiMessageRequestedCopyWith(ConnectionEvent_AiMessageRequested value, $Res Function(ConnectionEvent_AiMessageRequested) _then) = _$ConnectionEvent_AiMessageRequestedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String text
});




}
/// @nodoc
class _$ConnectionEvent_AiMessageRequestedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiMessageRequestedCopyWith<$Res> {
  _$ConnectionEvent_AiMessageRequestedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiMessageRequested _self;
  final $Res Function(ConnectionEvent_AiMessageRequested) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? text = null,}) {
  return _then(ConnectionEvent_AiMessageRequested(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiActivateRequested extends ConnectionEvent {
  const ConnectionEvent_AiActivateRequested({required this.deviceId}): super._();
  

 final  String deviceId;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiActivateRequestedCopyWith<ConnectionEvent_AiActivateRequested> get copyWith => _$ConnectionEvent_AiActivateRequestedCopyWithImpl<ConnectionEvent_AiActivateRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiActivateRequested&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId);

@override
String toString() {
  return 'ConnectionEvent.aiActivateRequested(deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiActivateRequestedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiActivateRequestedCopyWith(ConnectionEvent_AiActivateRequested value, $Res Function(ConnectionEvent_AiActivateRequested) _then) = _$ConnectionEvent_AiActivateRequestedCopyWithImpl;
@useResult
$Res call({
 String deviceId
});




}
/// @nodoc
class _$ConnectionEvent_AiActivateRequestedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiActivateRequestedCopyWith<$Res> {
  _$ConnectionEvent_AiActivateRequestedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiActivateRequested _self;
  final $Res Function(ConnectionEvent_AiActivateRequested) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,}) {
  return _then(ConnectionEvent_AiActivateRequested(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiApplyDraftRequested extends ConnectionEvent {
  const ConnectionEvent_AiApplyDraftRequested({required this.deviceId, required this.draft}): super._();
  

 final  String deviceId;
 final  AiRemoteDraft draft;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiApplyDraftRequestedCopyWith<ConnectionEvent_AiApplyDraftRequested> get copyWith => _$ConnectionEvent_AiApplyDraftRequestedCopyWithImpl<ConnectionEvent_AiApplyDraftRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiApplyDraftRequested&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.draft, draft) || other.draft == draft));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,draft);

@override
String toString() {
  return 'ConnectionEvent.aiApplyDraftRequested(deviceId: $deviceId, draft: $draft)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiApplyDraftRequestedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiApplyDraftRequestedCopyWith(ConnectionEvent_AiApplyDraftRequested value, $Res Function(ConnectionEvent_AiApplyDraftRequested) _then) = _$ConnectionEvent_AiApplyDraftRequestedCopyWithImpl;
@useResult
$Res call({
 String deviceId, AiRemoteDraft draft
});




}
/// @nodoc
class _$ConnectionEvent_AiApplyDraftRequestedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiApplyDraftRequestedCopyWith<$Res> {
  _$ConnectionEvent_AiApplyDraftRequestedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiApplyDraftRequested _self;
  final $Res Function(ConnectionEvent_AiApplyDraftRequested) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? draft = null,}) {
  return _then(ConnectionEvent_AiApplyDraftRequested(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as AiRemoteDraft,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiRunDraftRequested extends ConnectionEvent {
  const ConnectionEvent_AiRunDraftRequested({required this.deviceId, required this.draft}): super._();
  

 final  String deviceId;
 final  AiRemoteDraft draft;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiRunDraftRequestedCopyWith<ConnectionEvent_AiRunDraftRequested> get copyWith => _$ConnectionEvent_AiRunDraftRequestedCopyWithImpl<ConnectionEvent_AiRunDraftRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiRunDraftRequested&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.draft, draft) || other.draft == draft));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,draft);

@override
String toString() {
  return 'ConnectionEvent.aiRunDraftRequested(deviceId: $deviceId, draft: $draft)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiRunDraftRequestedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiRunDraftRequestedCopyWith(ConnectionEvent_AiRunDraftRequested value, $Res Function(ConnectionEvent_AiRunDraftRequested) _then) = _$ConnectionEvent_AiRunDraftRequestedCopyWithImpl;
@useResult
$Res call({
 String deviceId, AiRemoteDraft draft
});




}
/// @nodoc
class _$ConnectionEvent_AiRunDraftRequestedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiRunDraftRequestedCopyWith<$Res> {
  _$ConnectionEvent_AiRunDraftRequestedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiRunDraftRequested _self;
  final $Res Function(ConnectionEvent_AiRunDraftRequested) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? draft = null,}) {
  return _then(ConnectionEvent_AiRunDraftRequested(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as AiRemoteDraft,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiAskAboutProcessRequested extends ConnectionEvent {
  const ConnectionEvent_AiAskAboutProcessRequested({required this.deviceId, required this.group}): super._();
  

 final  String deviceId;
 final  ProcessGroup group;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiAskAboutProcessRequestedCopyWith<ConnectionEvent_AiAskAboutProcessRequested> get copyWith => _$ConnectionEvent_AiAskAboutProcessRequestedCopyWithImpl<ConnectionEvent_AiAskAboutProcessRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiAskAboutProcessRequested&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.group, group) || other.group == group));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,group);

@override
String toString() {
  return 'ConnectionEvent.aiAskAboutProcessRequested(deviceId: $deviceId, group: $group)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiAskAboutProcessRequestedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiAskAboutProcessRequestedCopyWith(ConnectionEvent_AiAskAboutProcessRequested value, $Res Function(ConnectionEvent_AiAskAboutProcessRequested) _then) = _$ConnectionEvent_AiAskAboutProcessRequestedCopyWithImpl;
@useResult
$Res call({
 String deviceId, ProcessGroup group
});




}
/// @nodoc
class _$ConnectionEvent_AiAskAboutProcessRequestedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiAskAboutProcessRequestedCopyWith<$Res> {
  _$ConnectionEvent_AiAskAboutProcessRequestedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiAskAboutProcessRequested _self;
  final $Res Function(ConnectionEvent_AiAskAboutProcessRequested) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? group = null,}) {
  return _then(ConnectionEvent_AiAskAboutProcessRequested(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,group: null == group ? _self.group : group // ignore: cast_nullable_to_non_nullable
as ProcessGroup,
  ));
}


}

/// @nodoc


class ConnectionEvent_Connected extends ConnectionEvent {
  const ConnectionEvent_Connected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_Connected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionEvent.connected()';
}


}




/// @nodoc


class ConnectionEvent_Disconnected extends ConnectionEvent {
  const ConnectionEvent_Disconnected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionEvent.disconnected()';
}


}




/// @nodoc


class ConnectionEvent_HardwareSnapshotReceived extends ConnectionEvent {
  const ConnectionEvent_HardwareSnapshotReceived(this.field0): super._();
  

 final  HardwareSnapshot field0;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_HardwareSnapshotReceivedCopyWith<ConnectionEvent_HardwareSnapshotReceived> get copyWith => _$ConnectionEvent_HardwareSnapshotReceivedCopyWithImpl<ConnectionEvent_HardwareSnapshotReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_HardwareSnapshotReceived&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ConnectionEvent.hardwareSnapshotReceived(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_HardwareSnapshotReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_HardwareSnapshotReceivedCopyWith(ConnectionEvent_HardwareSnapshotReceived value, $Res Function(ConnectionEvent_HardwareSnapshotReceived) _then) = _$ConnectionEvent_HardwareSnapshotReceivedCopyWithImpl;
@useResult
$Res call({
 HardwareSnapshot field0
});




}
/// @nodoc
class _$ConnectionEvent_HardwareSnapshotReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_HardwareSnapshotReceivedCopyWith<$Res> {
  _$ConnectionEvent_HardwareSnapshotReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_HardwareSnapshotReceived _self;
  final $Res Function(ConnectionEvent_HardwareSnapshotReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ConnectionEvent_HardwareSnapshotReceived(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as HardwareSnapshot,
  ));
}


}

/// @nodoc


class ConnectionEvent_ActionsCatalogReceived extends ConnectionEvent {
  const ConnectionEvent_ActionsCatalogReceived(final  List<RemoteAction> field0): _field0 = field0,super._();
  

 final  List<RemoteAction> _field0;
 List<RemoteAction> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_ActionsCatalogReceivedCopyWith<ConnectionEvent_ActionsCatalogReceived> get copyWith => _$ConnectionEvent_ActionsCatalogReceivedCopyWithImpl<ConnectionEvent_ActionsCatalogReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_ActionsCatalogReceived&&const DeepCollectionEquality().equals(other._field0, _field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));

@override
String toString() {
  return 'ConnectionEvent.actionsCatalogReceived(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_ActionsCatalogReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_ActionsCatalogReceivedCopyWith(ConnectionEvent_ActionsCatalogReceived value, $Res Function(ConnectionEvent_ActionsCatalogReceived) _then) = _$ConnectionEvent_ActionsCatalogReceivedCopyWithImpl;
@useResult
$Res call({
 List<RemoteAction> field0
});




}
/// @nodoc
class _$ConnectionEvent_ActionsCatalogReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_ActionsCatalogReceivedCopyWith<$Res> {
  _$ConnectionEvent_ActionsCatalogReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_ActionsCatalogReceived _self;
  final $Res Function(ConnectionEvent_ActionsCatalogReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ConnectionEvent_ActionsCatalogReceived(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<RemoteAction>,
  ));
}


}

/// @nodoc


class ConnectionEvent_ActionAckReceived extends ConnectionEvent {
  const ConnectionEvent_ActionAckReceived({required this.actionId, required this.success, this.error}): super._();
  

 final  String actionId;
 final  bool success;
 final  String? error;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_ActionAckReceivedCopyWith<ConnectionEvent_ActionAckReceived> get copyWith => _$ConnectionEvent_ActionAckReceivedCopyWithImpl<ConnectionEvent_ActionAckReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_ActionAckReceived&&(identical(other.actionId, actionId) || other.actionId == actionId)&&(identical(other.success, success) || other.success == success)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,actionId,success,error);

@override
String toString() {
  return 'ConnectionEvent.actionAckReceived(actionId: $actionId, success: $success, error: $error)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_ActionAckReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_ActionAckReceivedCopyWith(ConnectionEvent_ActionAckReceived value, $Res Function(ConnectionEvent_ActionAckReceived) _then) = _$ConnectionEvent_ActionAckReceivedCopyWithImpl;
@useResult
$Res call({
 String actionId, bool success, String? error
});




}
/// @nodoc
class _$ConnectionEvent_ActionAckReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_ActionAckReceivedCopyWith<$Res> {
  _$ConnectionEvent_ActionAckReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_ActionAckReceived _self;
  final $Res Function(ConnectionEvent_ActionAckReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? actionId = null,Object? success = null,Object? error = freezed,}) {
  return _then(ConnectionEvent_ActionAckReceived(
actionId: null == actionId ? _self.actionId : actionId // ignore: cast_nullable_to_non_nullable
as String,success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ConnectionEvent_RelayOfferReceived extends ConnectionEvent {
  const ConnectionEvent_RelayOfferReceived({required this.host, required this.port, required this.tokenHex}): super._();
  

 final  String host;
 final  int port;
 final  String tokenHex;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_RelayOfferReceivedCopyWith<ConnectionEvent_RelayOfferReceived> get copyWith => _$ConnectionEvent_RelayOfferReceivedCopyWithImpl<ConnectionEvent_RelayOfferReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_RelayOfferReceived&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.tokenHex, tokenHex) || other.tokenHex == tokenHex));
}


@override
int get hashCode => Object.hash(runtimeType,host,port,tokenHex);

@override
String toString() {
  return 'ConnectionEvent.relayOfferReceived(host: $host, port: $port, tokenHex: $tokenHex)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_RelayOfferReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_RelayOfferReceivedCopyWith(ConnectionEvent_RelayOfferReceived value, $Res Function(ConnectionEvent_RelayOfferReceived) _then) = _$ConnectionEvent_RelayOfferReceivedCopyWithImpl;
@useResult
$Res call({
 String host, int port, String tokenHex
});




}
/// @nodoc
class _$ConnectionEvent_RelayOfferReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_RelayOfferReceivedCopyWith<$Res> {
  _$ConnectionEvent_RelayOfferReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_RelayOfferReceived _self;
  final $Res Function(ConnectionEvent_RelayOfferReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? port = null,Object? tokenHex = null,}) {
  return _then(ConnectionEvent_RelayOfferReceived(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,tokenHex: null == tokenHex ? _self.tokenHex : tokenHex // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectionEvent_TopProcessesReceived extends ConnectionEvent {
  const ConnectionEvent_TopProcessesReceived(this.field0): super._();
  

 final  TopProcesses field0;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_TopProcessesReceivedCopyWith<ConnectionEvent_TopProcessesReceived> get copyWith => _$ConnectionEvent_TopProcessesReceivedCopyWithImpl<ConnectionEvent_TopProcessesReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_TopProcessesReceived&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ConnectionEvent.topProcessesReceived(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_TopProcessesReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_TopProcessesReceivedCopyWith(ConnectionEvent_TopProcessesReceived value, $Res Function(ConnectionEvent_TopProcessesReceived) _then) = _$ConnectionEvent_TopProcessesReceivedCopyWithImpl;
@useResult
$Res call({
 TopProcesses field0
});




}
/// @nodoc
class _$ConnectionEvent_TopProcessesReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_TopProcessesReceivedCopyWith<$Res> {
  _$ConnectionEvent_TopProcessesReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_TopProcessesReceived _self;
  final $Res Function(ConnectionEvent_TopProcessesReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ConnectionEvent_TopProcessesReceived(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as TopProcesses,
  ));
}


}

/// @nodoc


class ConnectionEvent_ProcessTerminatedReceived extends ConnectionEvent {
  const ConnectionEvent_ProcessTerminatedReceived({required this.name, required this.killed, required this.failed, this.rejectedReason}): super._();
  

 final  String name;
 final  int killed;
 final  int failed;
/// Con texto cuando la PC rechazo el pedido entero.
 final  String? rejectedReason;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_ProcessTerminatedReceivedCopyWith<ConnectionEvent_ProcessTerminatedReceived> get copyWith => _$ConnectionEvent_ProcessTerminatedReceivedCopyWithImpl<ConnectionEvent_ProcessTerminatedReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_ProcessTerminatedReceived&&(identical(other.name, name) || other.name == name)&&(identical(other.killed, killed) || other.killed == killed)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.rejectedReason, rejectedReason) || other.rejectedReason == rejectedReason));
}


@override
int get hashCode => Object.hash(runtimeType,name,killed,failed,rejectedReason);

@override
String toString() {
  return 'ConnectionEvent.processTerminatedReceived(name: $name, killed: $killed, failed: $failed, rejectedReason: $rejectedReason)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_ProcessTerminatedReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_ProcessTerminatedReceivedCopyWith(ConnectionEvent_ProcessTerminatedReceived value, $Res Function(ConnectionEvent_ProcessTerminatedReceived) _then) = _$ConnectionEvent_ProcessTerminatedReceivedCopyWithImpl;
@useResult
$Res call({
 String name, int killed, int failed, String? rejectedReason
});




}
/// @nodoc
class _$ConnectionEvent_ProcessTerminatedReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_ProcessTerminatedReceivedCopyWith<$Res> {
  _$ConnectionEvent_ProcessTerminatedReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_ProcessTerminatedReceived _self;
  final $Res Function(ConnectionEvent_ProcessTerminatedReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? killed = null,Object? failed = null,Object? rejectedReason = freezed,}) {
  return _then(ConnectionEvent_ProcessTerminatedReceived(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,killed: null == killed ? _self.killed : killed // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,rejectedReason: freezed == rejectedReason ? _self.rejectedReason : rejectedReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ConnectionEvent_ActionRunUpdateReceived extends ConnectionEvent {
  const ConnectionEvent_ActionRunUpdateReceived({required this.runId, required this.actionId, required this.phase, this.exitCode, required this.elapsedMs, required this.outputTail}): super._();
  

 final  String runId;
 final  String actionId;
 final  RunPhase phase;
 final  int? exitCode;
 final  int elapsedMs;
 final  String outputTail;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_ActionRunUpdateReceivedCopyWith<ConnectionEvent_ActionRunUpdateReceived> get copyWith => _$ConnectionEvent_ActionRunUpdateReceivedCopyWithImpl<ConnectionEvent_ActionRunUpdateReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_ActionRunUpdateReceived&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.actionId, actionId) || other.actionId == actionId)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.elapsedMs, elapsedMs) || other.elapsedMs == elapsedMs)&&(identical(other.outputTail, outputTail) || other.outputTail == outputTail));
}


@override
int get hashCode => Object.hash(runtimeType,runId,actionId,phase,exitCode,elapsedMs,outputTail);

@override
String toString() {
  return 'ConnectionEvent.actionRunUpdateReceived(runId: $runId, actionId: $actionId, phase: $phase, exitCode: $exitCode, elapsedMs: $elapsedMs, outputTail: $outputTail)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_ActionRunUpdateReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_ActionRunUpdateReceivedCopyWith(ConnectionEvent_ActionRunUpdateReceived value, $Res Function(ConnectionEvent_ActionRunUpdateReceived) _then) = _$ConnectionEvent_ActionRunUpdateReceivedCopyWithImpl;
@useResult
$Res call({
 String runId, String actionId, RunPhase phase, int? exitCode, int elapsedMs, String outputTail
});




}
/// @nodoc
class _$ConnectionEvent_ActionRunUpdateReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_ActionRunUpdateReceivedCopyWith<$Res> {
  _$ConnectionEvent_ActionRunUpdateReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_ActionRunUpdateReceived _self;
  final $Res Function(ConnectionEvent_ActionRunUpdateReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? actionId = null,Object? phase = null,Object? exitCode = freezed,Object? elapsedMs = null,Object? outputTail = null,}) {
  return _then(ConnectionEvent_ActionRunUpdateReceived(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,actionId: null == actionId ? _self.actionId : actionId // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as RunPhase,exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as int,outputTail: null == outputTail ? _self.outputTail : outputTail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectionEvent_HubSubscriptionsSnapshotReceived extends ConnectionEvent {
  const ConnectionEvent_HubSubscriptionsSnapshotReceived(final  List<HubSubscriptionSummary> field0): _field0 = field0,super._();
  

 final  List<HubSubscriptionSummary> _field0;
 List<HubSubscriptionSummary> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWith<ConnectionEvent_HubSubscriptionsSnapshotReceived> get copyWith => _$ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWithImpl<ConnectionEvent_HubSubscriptionsSnapshotReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_HubSubscriptionsSnapshotReceived&&const DeepCollectionEquality().equals(other._field0, _field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));

@override
String toString() {
  return 'ConnectionEvent.hubSubscriptionsSnapshotReceived(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWith(ConnectionEvent_HubSubscriptionsSnapshotReceived value, $Res Function(ConnectionEvent_HubSubscriptionsSnapshotReceived) _then) = _$ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWithImpl;
@useResult
$Res call({
 List<HubSubscriptionSummary> field0
});




}
/// @nodoc
class _$ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWith<$Res> {
  _$ConnectionEvent_HubSubscriptionsSnapshotReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_HubSubscriptionsSnapshotReceived _self;
  final $Res Function(ConnectionEvent_HubSubscriptionsSnapshotReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ConnectionEvent_HubSubscriptionsSnapshotReceived(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<HubSubscriptionSummary>,
  ));
}


}

/// @nodoc


class ConnectionEvent_HostComponentsReceived extends ConnectionEvent {
  const ConnectionEvent_HostComponentsReceived(this.field0): super._();
  

 final  HostComponents field0;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_HostComponentsReceivedCopyWith<ConnectionEvent_HostComponentsReceived> get copyWith => _$ConnectionEvent_HostComponentsReceivedCopyWithImpl<ConnectionEvent_HostComponentsReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_HostComponentsReceived&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ConnectionEvent.hostComponentsReceived(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_HostComponentsReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_HostComponentsReceivedCopyWith(ConnectionEvent_HostComponentsReceived value, $Res Function(ConnectionEvent_HostComponentsReceived) _then) = _$ConnectionEvent_HostComponentsReceivedCopyWithImpl;
@useResult
$Res call({
 HostComponents field0
});




}
/// @nodoc
class _$ConnectionEvent_HostComponentsReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_HostComponentsReceivedCopyWith<$Res> {
  _$ConnectionEvent_HostComponentsReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_HostComponentsReceived _self;
  final $Res Function(ConnectionEvent_HostComponentsReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ConnectionEvent_HostComponentsReceived(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as HostComponents,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiStatusReceived extends ConnectionEvent {
  const ConnectionEvent_AiStatusReceived({required this.enabled, required this.ready}): super._();
  

 final  bool enabled;
 final  bool ready;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiStatusReceivedCopyWith<ConnectionEvent_AiStatusReceived> get copyWith => _$ConnectionEvent_AiStatusReceivedCopyWithImpl<ConnectionEvent_AiStatusReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiStatusReceived&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.ready, ready) || other.ready == ready));
}


@override
int get hashCode => Object.hash(runtimeType,enabled,ready);

@override
String toString() {
  return 'ConnectionEvent.aiStatusReceived(enabled: $enabled, ready: $ready)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiStatusReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiStatusReceivedCopyWith(ConnectionEvent_AiStatusReceived value, $Res Function(ConnectionEvent_AiStatusReceived) _then) = _$ConnectionEvent_AiStatusReceivedCopyWithImpl;
@useResult
$Res call({
 bool enabled, bool ready
});




}
/// @nodoc
class _$ConnectionEvent_AiStatusReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiStatusReceivedCopyWith<$Res> {
  _$ConnectionEvent_AiStatusReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiStatusReceived _self;
  final $Res Function(ConnectionEvent_AiStatusReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? ready = null,}) {
  return _then(ConnectionEvent_AiStatusReceived(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,ready: null == ready ? _self.ready : ready // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ConnectionEvent_AiChatEventReceived extends ConnectionEvent {
  const ConnectionEvent_AiChatEventReceived(this.field0): super._();
  

 final  AiRemoteChatEvent field0;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_AiChatEventReceivedCopyWith<ConnectionEvent_AiChatEventReceived> get copyWith => _$ConnectionEvent_AiChatEventReceivedCopyWithImpl<ConnectionEvent_AiChatEventReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_AiChatEventReceived&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ConnectionEvent.aiChatEventReceived(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_AiChatEventReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_AiChatEventReceivedCopyWith(ConnectionEvent_AiChatEventReceived value, $Res Function(ConnectionEvent_AiChatEventReceived) _then) = _$ConnectionEvent_AiChatEventReceivedCopyWithImpl;
@useResult
$Res call({
 AiRemoteChatEvent field0
});


$AiRemoteChatEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$ConnectionEvent_AiChatEventReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_AiChatEventReceivedCopyWith<$Res> {
  _$ConnectionEvent_AiChatEventReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_AiChatEventReceived _self;
  final $Res Function(ConnectionEvent_AiChatEventReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ConnectionEvent_AiChatEventReceived(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as AiRemoteChatEvent,
  ));
}

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AiRemoteChatEventCopyWith<$Res> get field0 {
  
  return $AiRemoteChatEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class ConnectionEvent_NotesResponseReceived extends ConnectionEvent {
  const ConnectionEvent_NotesResponseReceived({required this.requestId, required this.response}): super._();
  

 final  String requestId;
 final  NotesReply response;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionEvent_NotesResponseReceivedCopyWith<ConnectionEvent_NotesResponseReceived> get copyWith => _$ConnectionEvent_NotesResponseReceivedCopyWithImpl<ConnectionEvent_NotesResponseReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_NotesResponseReceived&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.response, response) || other.response == response));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,response);

@override
String toString() {
  return 'ConnectionEvent.notesResponseReceived(requestId: $requestId, response: $response)';
}


}

/// @nodoc
abstract mixin class $ConnectionEvent_NotesResponseReceivedCopyWith<$Res> implements $ConnectionEventCopyWith<$Res> {
  factory $ConnectionEvent_NotesResponseReceivedCopyWith(ConnectionEvent_NotesResponseReceived value, $Res Function(ConnectionEvent_NotesResponseReceived) _then) = _$ConnectionEvent_NotesResponseReceivedCopyWithImpl;
@useResult
$Res call({
 String requestId, NotesReply response
});


$NotesReplyCopyWith<$Res> get response;

}
/// @nodoc
class _$ConnectionEvent_NotesResponseReceivedCopyWithImpl<$Res>
    implements $ConnectionEvent_NotesResponseReceivedCopyWith<$Res> {
  _$ConnectionEvent_NotesResponseReceivedCopyWithImpl(this._self, this._then);

  final ConnectionEvent_NotesResponseReceived _self;
  final $Res Function(ConnectionEvent_NotesResponseReceived) _then;

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? response = null,}) {
  return _then(ConnectionEvent_NotesResponseReceived(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,response: null == response ? _self.response : response // ignore: cast_nullable_to_non_nullable
as NotesReply,
  ));
}

/// Create a copy of ConnectionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NotesReplyCopyWith<$Res> get response {
  
  return $NotesReplyCopyWith<$Res>(_self.response, (value) {
    return _then(_self.copyWith(response: value));
  });
}
}

/// @nodoc


class ConnectionEvent_NotesChanged extends ConnectionEvent {
  const ConnectionEvent_NotesChanged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionEvent_NotesChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionEvent.notesChanged()';
}


}




/// @nodoc
mixin _$NoteOp {

 String get path; String? get baseHash;
/// Create a copy of NoteOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOpCopyWith<NoteOp> get copyWith => _$NoteOpCopyWithImpl<NoteOp>(this as NoteOp, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOp&&(identical(other.path, path) || other.path == path)&&(identical(other.baseHash, baseHash) || other.baseHash == baseHash));
}


@override
int get hashCode => Object.hash(runtimeType,path,baseHash);

@override
String toString() {
  return 'NoteOp(path: $path, baseHash: $baseHash)';
}


}

/// @nodoc
abstract mixin class $NoteOpCopyWith<$Res>  {
  factory $NoteOpCopyWith(NoteOp value, $Res Function(NoteOp) _then) = _$NoteOpCopyWithImpl;
@useResult
$Res call({
 String path, String? baseHash
});




}
/// @nodoc
class _$NoteOpCopyWithImpl<$Res>
    implements $NoteOpCopyWith<$Res> {
  _$NoteOpCopyWithImpl(this._self, this._then);

  final NoteOp _self;
  final $Res Function(NoteOp) _then;

/// Create a copy of NoteOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? baseHash = freezed,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,baseHash: freezed == baseHash ? _self.baseHash : baseHash // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [NoteOp].
extension NoteOpPatterns on NoteOp {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NoteOp_Save value)?  save,TResult Function( NoteOp_Delete value)?  delete,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NoteOp_Save() when save != null:
return save(_that);case NoteOp_Delete() when delete != null:
return delete(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NoteOp_Save value)  save,required TResult Function( NoteOp_Delete value)  delete,}){
final _that = this;
switch (_that) {
case NoteOp_Save():
return save(_that);case NoteOp_Delete():
return delete(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NoteOp_Save value)?  save,TResult? Function( NoteOp_Delete value)?  delete,}){
final _that = this;
switch (_that) {
case NoteOp_Save() when save != null:
return save(_that);case NoteOp_Delete() when delete != null:
return delete(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path,  String text,  String? baseHash)?  save,TResult Function( String path,  String? baseHash)?  delete,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NoteOp_Save() when save != null:
return save(_that.path,_that.text,_that.baseHash);case NoteOp_Delete() when delete != null:
return delete(_that.path,_that.baseHash);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path,  String text,  String? baseHash)  save,required TResult Function( String path,  String? baseHash)  delete,}) {final _that = this;
switch (_that) {
case NoteOp_Save():
return save(_that.path,_that.text,_that.baseHash);case NoteOp_Delete():
return delete(_that.path,_that.baseHash);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path,  String text,  String? baseHash)?  save,TResult? Function( String path,  String? baseHash)?  delete,}) {final _that = this;
switch (_that) {
case NoteOp_Save() when save != null:
return save(_that.path,_that.text,_that.baseHash);case NoteOp_Delete() when delete != null:
return delete(_that.path,_that.baseHash);case _:
  return null;

}
}

}

/// @nodoc


class NoteOp_Save extends NoteOp {
  const NoteOp_Save({required this.path, required this.text, this.baseHash}): super._();
  

@override final  String path;
 final  String text;
@override final  String? baseHash;

/// Create a copy of NoteOp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOp_SaveCopyWith<NoteOp_Save> get copyWith => _$NoteOp_SaveCopyWithImpl<NoteOp_Save>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOp_Save&&(identical(other.path, path) || other.path == path)&&(identical(other.text, text) || other.text == text)&&(identical(other.baseHash, baseHash) || other.baseHash == baseHash));
}


@override
int get hashCode => Object.hash(runtimeType,path,text,baseHash);

@override
String toString() {
  return 'NoteOp.save(path: $path, text: $text, baseHash: $baseHash)';
}


}

/// @nodoc
abstract mixin class $NoteOp_SaveCopyWith<$Res> implements $NoteOpCopyWith<$Res> {
  factory $NoteOp_SaveCopyWith(NoteOp_Save value, $Res Function(NoteOp_Save) _then) = _$NoteOp_SaveCopyWithImpl;
@override @useResult
$Res call({
 String path, String text, String? baseHash
});




}
/// @nodoc
class _$NoteOp_SaveCopyWithImpl<$Res>
    implements $NoteOp_SaveCopyWith<$Res> {
  _$NoteOp_SaveCopyWithImpl(this._self, this._then);

  final NoteOp_Save _self;
  final $Res Function(NoteOp_Save) _then;

/// Create a copy of NoteOp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? text = null,Object? baseHash = freezed,}) {
  return _then(NoteOp_Save(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,baseHash: freezed == baseHash ? _self.baseHash : baseHash // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class NoteOp_Delete extends NoteOp {
  const NoteOp_Delete({required this.path, this.baseHash}): super._();
  

@override final  String path;
@override final  String? baseHash;

/// Create a copy of NoteOp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOp_DeleteCopyWith<NoteOp_Delete> get copyWith => _$NoteOp_DeleteCopyWithImpl<NoteOp_Delete>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOp_Delete&&(identical(other.path, path) || other.path == path)&&(identical(other.baseHash, baseHash) || other.baseHash == baseHash));
}


@override
int get hashCode => Object.hash(runtimeType,path,baseHash);

@override
String toString() {
  return 'NoteOp.delete(path: $path, baseHash: $baseHash)';
}


}

/// @nodoc
abstract mixin class $NoteOp_DeleteCopyWith<$Res> implements $NoteOpCopyWith<$Res> {
  factory $NoteOp_DeleteCopyWith(NoteOp_Delete value, $Res Function(NoteOp_Delete) _then) = _$NoteOp_DeleteCopyWithImpl;
@override @useResult
$Res call({
 String path, String? baseHash
});




}
/// @nodoc
class _$NoteOp_DeleteCopyWithImpl<$Res>
    implements $NoteOp_DeleteCopyWith<$Res> {
  _$NoteOp_DeleteCopyWithImpl(this._self, this._then);

  final NoteOp_Delete _self;
  final $Res Function(NoteOp_Delete) _then;

/// Create a copy of NoteOp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? baseHash = freezed,}) {
  return _then(NoteOp_Delete(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,baseHash: freezed == baseHash ? _self.baseHash : baseHash // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$NoteOpResult {

 String get path;
/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOpResultCopyWith<NoteOpResult> get copyWith => _$NoteOpResultCopyWithImpl<NoteOpResult>(this as NoteOpResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOpResult&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'NoteOpResult(path: $path)';
}


}

/// @nodoc
abstract mixin class $NoteOpResultCopyWith<$Res>  {
  factory $NoteOpResultCopyWith(NoteOpResult value, $Res Function(NoteOpResult) _then) = _$NoteOpResultCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$NoteOpResultCopyWithImpl<$Res>
    implements $NoteOpResultCopyWith<$Res> {
  _$NoteOpResultCopyWithImpl(this._self, this._then);

  final NoteOpResult _self;
  final $Res Function(NoteOpResult) _then;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [NoteOpResult].
extension NoteOpResultPatterns on NoteOpResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NoteOpResult_Saved value)?  saved,TResult Function( NoteOpResult_Deleted value)?  deleted,TResult Function( NoteOpResult_Conflict value)?  conflict,TResult Function( NoteOpResult_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NoteOpResult_Saved() when saved != null:
return saved(_that);case NoteOpResult_Deleted() when deleted != null:
return deleted(_that);case NoteOpResult_Conflict() when conflict != null:
return conflict(_that);case NoteOpResult_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NoteOpResult_Saved value)  saved,required TResult Function( NoteOpResult_Deleted value)  deleted,required TResult Function( NoteOpResult_Conflict value)  conflict,required TResult Function( NoteOpResult_Failed value)  failed,}){
final _that = this;
switch (_that) {
case NoteOpResult_Saved():
return saved(_that);case NoteOpResult_Deleted():
return deleted(_that);case NoteOpResult_Conflict():
return conflict(_that);case NoteOpResult_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NoteOpResult_Saved value)?  saved,TResult? Function( NoteOpResult_Deleted value)?  deleted,TResult? Function( NoteOpResult_Conflict value)?  conflict,TResult? Function( NoteOpResult_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case NoteOpResult_Saved() when saved != null:
return saved(_that);case NoteOpResult_Deleted() when deleted != null:
return deleted(_that);case NoteOpResult_Conflict() when conflict != null:
return conflict(_that);case NoteOpResult_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path,  String hash)?  saved,TResult Function( String path)?  deleted,TResult Function( String path,  String diskText,  String diskHash)?  conflict,TResult Function( String path,  String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NoteOpResult_Saved() when saved != null:
return saved(_that.path,_that.hash);case NoteOpResult_Deleted() when deleted != null:
return deleted(_that.path);case NoteOpResult_Conflict() when conflict != null:
return conflict(_that.path,_that.diskText,_that.diskHash);case NoteOpResult_Failed() when failed != null:
return failed(_that.path,_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path,  String hash)  saved,required TResult Function( String path)  deleted,required TResult Function( String path,  String diskText,  String diskHash)  conflict,required TResult Function( String path,  String detail)  failed,}) {final _that = this;
switch (_that) {
case NoteOpResult_Saved():
return saved(_that.path,_that.hash);case NoteOpResult_Deleted():
return deleted(_that.path);case NoteOpResult_Conflict():
return conflict(_that.path,_that.diskText,_that.diskHash);case NoteOpResult_Failed():
return failed(_that.path,_that.detail);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path,  String hash)?  saved,TResult? Function( String path)?  deleted,TResult? Function( String path,  String diskText,  String diskHash)?  conflict,TResult? Function( String path,  String detail)?  failed,}) {final _that = this;
switch (_that) {
case NoteOpResult_Saved() when saved != null:
return saved(_that.path,_that.hash);case NoteOpResult_Deleted() when deleted != null:
return deleted(_that.path);case NoteOpResult_Conflict() when conflict != null:
return conflict(_that.path,_that.diskText,_that.diskHash);case NoteOpResult_Failed() when failed != null:
return failed(_that.path,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class NoteOpResult_Saved extends NoteOpResult {
  const NoteOpResult_Saved({required this.path, required this.hash}): super._();
  

@override final  String path;
 final  String hash;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOpResult_SavedCopyWith<NoteOpResult_Saved> get copyWith => _$NoteOpResult_SavedCopyWithImpl<NoteOpResult_Saved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOpResult_Saved&&(identical(other.path, path) || other.path == path)&&(identical(other.hash, hash) || other.hash == hash));
}


@override
int get hashCode => Object.hash(runtimeType,path,hash);

@override
String toString() {
  return 'NoteOpResult.saved(path: $path, hash: $hash)';
}


}

/// @nodoc
abstract mixin class $NoteOpResult_SavedCopyWith<$Res> implements $NoteOpResultCopyWith<$Res> {
  factory $NoteOpResult_SavedCopyWith(NoteOpResult_Saved value, $Res Function(NoteOpResult_Saved) _then) = _$NoteOpResult_SavedCopyWithImpl;
@override @useResult
$Res call({
 String path, String hash
});




}
/// @nodoc
class _$NoteOpResult_SavedCopyWithImpl<$Res>
    implements $NoteOpResult_SavedCopyWith<$Res> {
  _$NoteOpResult_SavedCopyWithImpl(this._self, this._then);

  final NoteOpResult_Saved _self;
  final $Res Function(NoteOpResult_Saved) _then;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? hash = null,}) {
  return _then(NoteOpResult_Saved(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NoteOpResult_Deleted extends NoteOpResult {
  const NoteOpResult_Deleted({required this.path}): super._();
  

@override final  String path;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOpResult_DeletedCopyWith<NoteOpResult_Deleted> get copyWith => _$NoteOpResult_DeletedCopyWithImpl<NoteOpResult_Deleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOpResult_Deleted&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'NoteOpResult.deleted(path: $path)';
}


}

/// @nodoc
abstract mixin class $NoteOpResult_DeletedCopyWith<$Res> implements $NoteOpResultCopyWith<$Res> {
  factory $NoteOpResult_DeletedCopyWith(NoteOpResult_Deleted value, $Res Function(NoteOpResult_Deleted) _then) = _$NoteOpResult_DeletedCopyWithImpl;
@override @useResult
$Res call({
 String path
});




}
/// @nodoc
class _$NoteOpResult_DeletedCopyWithImpl<$Res>
    implements $NoteOpResult_DeletedCopyWith<$Res> {
  _$NoteOpResult_DeletedCopyWithImpl(this._self, this._then);

  final NoteOpResult_Deleted _self;
  final $Res Function(NoteOpResult_Deleted) _then;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(NoteOpResult_Deleted(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NoteOpResult_Conflict extends NoteOpResult {
  const NoteOpResult_Conflict({required this.path, required this.diskText, required this.diskHash}): super._();
  

@override final  String path;
 final  String diskText;
 final  String diskHash;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOpResult_ConflictCopyWith<NoteOpResult_Conflict> get copyWith => _$NoteOpResult_ConflictCopyWithImpl<NoteOpResult_Conflict>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOpResult_Conflict&&(identical(other.path, path) || other.path == path)&&(identical(other.diskText, diskText) || other.diskText == diskText)&&(identical(other.diskHash, diskHash) || other.diskHash == diskHash));
}


@override
int get hashCode => Object.hash(runtimeType,path,diskText,diskHash);

@override
String toString() {
  return 'NoteOpResult.conflict(path: $path, diskText: $diskText, diskHash: $diskHash)';
}


}

/// @nodoc
abstract mixin class $NoteOpResult_ConflictCopyWith<$Res> implements $NoteOpResultCopyWith<$Res> {
  factory $NoteOpResult_ConflictCopyWith(NoteOpResult_Conflict value, $Res Function(NoteOpResult_Conflict) _then) = _$NoteOpResult_ConflictCopyWithImpl;
@override @useResult
$Res call({
 String path, String diskText, String diskHash
});




}
/// @nodoc
class _$NoteOpResult_ConflictCopyWithImpl<$Res>
    implements $NoteOpResult_ConflictCopyWith<$Res> {
  _$NoteOpResult_ConflictCopyWithImpl(this._self, this._then);

  final NoteOpResult_Conflict _self;
  final $Res Function(NoteOpResult_Conflict) _then;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? diskText = null,Object? diskHash = null,}) {
  return _then(NoteOpResult_Conflict(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,diskText: null == diskText ? _self.diskText : diskText // ignore: cast_nullable_to_non_nullable
as String,diskHash: null == diskHash ? _self.diskHash : diskHash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NoteOpResult_Failed extends NoteOpResult {
  const NoteOpResult_Failed({required this.path, required this.detail}): super._();
  

@override final  String path;
 final  String detail;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteOpResult_FailedCopyWith<NoteOpResult_Failed> get copyWith => _$NoteOpResult_FailedCopyWithImpl<NoteOpResult_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteOpResult_Failed&&(identical(other.path, path) || other.path == path)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,path,detail);

@override
String toString() {
  return 'NoteOpResult.failed(path: $path, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $NoteOpResult_FailedCopyWith<$Res> implements $NoteOpResultCopyWith<$Res> {
  factory $NoteOpResult_FailedCopyWith(NoteOpResult_Failed value, $Res Function(NoteOpResult_Failed) _then) = _$NoteOpResult_FailedCopyWithImpl;
@override @useResult
$Res call({
 String path, String detail
});




}
/// @nodoc
class _$NoteOpResult_FailedCopyWithImpl<$Res>
    implements $NoteOpResult_FailedCopyWith<$Res> {
  _$NoteOpResult_FailedCopyWithImpl(this._self, this._then);

  final NoteOpResult_Failed _self;
  final $Res Function(NoteOpResult_Failed) _then;

/// Create a copy of NoteOpResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? detail = null,}) {
  return _then(NoteOpResult_Failed(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$NotesReply {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotesReply);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NotesReply()';
}


}

/// @nodoc
class $NotesReplyCopyWith<$Res>  {
$NotesReplyCopyWith(NotesReply _, $Res Function(NotesReply) __);
}


/// Adds pattern-matching-related methods to [NotesReply].
extension NotesReplyPatterns on NotesReply {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NotesReply_Manifest value)?  manifest,TResult Function( NotesReply_Fetch value)?  fetch,TResult Function( NotesReply_Applied value)?  applied,TResult Function( NotesReply_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NotesReply_Manifest() when manifest != null:
return manifest(_that);case NotesReply_Fetch() when fetch != null:
return fetch(_that);case NotesReply_Applied() when applied != null:
return applied(_that);case NotesReply_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NotesReply_Manifest value)  manifest,required TResult Function( NotesReply_Fetch value)  fetch,required TResult Function( NotesReply_Applied value)  applied,required TResult Function( NotesReply_Failed value)  failed,}){
final _that = this;
switch (_that) {
case NotesReply_Manifest():
return manifest(_that);case NotesReply_Fetch():
return fetch(_that);case NotesReply_Applied():
return applied(_that);case NotesReply_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NotesReply_Manifest value)?  manifest,TResult? Function( NotesReply_Fetch value)?  fetch,TResult? Function( NotesReply_Applied value)?  applied,TResult? Function( NotesReply_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case NotesReply_Manifest() when manifest != null:
return manifest(_that);case NotesReply_Fetch() when fetch != null:
return fetch(_that);case NotesReply_Applied() when applied != null:
return applied(_that);case NotesReply_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<NoteStamp> notes)?  manifest,TResult Function( List<NoteContent> notes)?  fetch,TResult Function( List<NoteOpResult> results)?  applied,TResult Function( String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NotesReply_Manifest() when manifest != null:
return manifest(_that.notes);case NotesReply_Fetch() when fetch != null:
return fetch(_that.notes);case NotesReply_Applied() when applied != null:
return applied(_that.results);case NotesReply_Failed() when failed != null:
return failed(_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<NoteStamp> notes)  manifest,required TResult Function( List<NoteContent> notes)  fetch,required TResult Function( List<NoteOpResult> results)  applied,required TResult Function( String detail)  failed,}) {final _that = this;
switch (_that) {
case NotesReply_Manifest():
return manifest(_that.notes);case NotesReply_Fetch():
return fetch(_that.notes);case NotesReply_Applied():
return applied(_that.results);case NotesReply_Failed():
return failed(_that.detail);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<NoteStamp> notes)?  manifest,TResult? Function( List<NoteContent> notes)?  fetch,TResult? Function( List<NoteOpResult> results)?  applied,TResult? Function( String detail)?  failed,}) {final _that = this;
switch (_that) {
case NotesReply_Manifest() when manifest != null:
return manifest(_that.notes);case NotesReply_Fetch() when fetch != null:
return fetch(_that.notes);case NotesReply_Applied() when applied != null:
return applied(_that.results);case NotesReply_Failed() when failed != null:
return failed(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class NotesReply_Manifest extends NotesReply {
  const NotesReply_Manifest({required final  List<NoteStamp> notes}): _notes = notes,super._();
  

 final  List<NoteStamp> _notes;
 List<NoteStamp> get notes {
  if (_notes is EqualUnmodifiableListView) return _notes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_notes);
}


/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotesReply_ManifestCopyWith<NotesReply_Manifest> get copyWith => _$NotesReply_ManifestCopyWithImpl<NotesReply_Manifest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotesReply_Manifest&&const DeepCollectionEquality().equals(other._notes, _notes));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_notes));

@override
String toString() {
  return 'NotesReply.manifest(notes: $notes)';
}


}

/// @nodoc
abstract mixin class $NotesReply_ManifestCopyWith<$Res> implements $NotesReplyCopyWith<$Res> {
  factory $NotesReply_ManifestCopyWith(NotesReply_Manifest value, $Res Function(NotesReply_Manifest) _then) = _$NotesReply_ManifestCopyWithImpl;
@useResult
$Res call({
 List<NoteStamp> notes
});




}
/// @nodoc
class _$NotesReply_ManifestCopyWithImpl<$Res>
    implements $NotesReply_ManifestCopyWith<$Res> {
  _$NotesReply_ManifestCopyWithImpl(this._self, this._then);

  final NotesReply_Manifest _self;
  final $Res Function(NotesReply_Manifest) _then;

/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? notes = null,}) {
  return _then(NotesReply_Manifest(
notes: null == notes ? _self._notes : notes // ignore: cast_nullable_to_non_nullable
as List<NoteStamp>,
  ));
}


}

/// @nodoc


class NotesReply_Fetch extends NotesReply {
  const NotesReply_Fetch({required final  List<NoteContent> notes}): _notes = notes,super._();
  

 final  List<NoteContent> _notes;
 List<NoteContent> get notes {
  if (_notes is EqualUnmodifiableListView) return _notes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_notes);
}


/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotesReply_FetchCopyWith<NotesReply_Fetch> get copyWith => _$NotesReply_FetchCopyWithImpl<NotesReply_Fetch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotesReply_Fetch&&const DeepCollectionEquality().equals(other._notes, _notes));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_notes));

@override
String toString() {
  return 'NotesReply.fetch(notes: $notes)';
}


}

/// @nodoc
abstract mixin class $NotesReply_FetchCopyWith<$Res> implements $NotesReplyCopyWith<$Res> {
  factory $NotesReply_FetchCopyWith(NotesReply_Fetch value, $Res Function(NotesReply_Fetch) _then) = _$NotesReply_FetchCopyWithImpl;
@useResult
$Res call({
 List<NoteContent> notes
});




}
/// @nodoc
class _$NotesReply_FetchCopyWithImpl<$Res>
    implements $NotesReply_FetchCopyWith<$Res> {
  _$NotesReply_FetchCopyWithImpl(this._self, this._then);

  final NotesReply_Fetch _self;
  final $Res Function(NotesReply_Fetch) _then;

/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? notes = null,}) {
  return _then(NotesReply_Fetch(
notes: null == notes ? _self._notes : notes // ignore: cast_nullable_to_non_nullable
as List<NoteContent>,
  ));
}


}

/// @nodoc


class NotesReply_Applied extends NotesReply {
  const NotesReply_Applied({required final  List<NoteOpResult> results}): _results = results,super._();
  

 final  List<NoteOpResult> _results;
 List<NoteOpResult> get results {
  if (_results is EqualUnmodifiableListView) return _results;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_results);
}


/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotesReply_AppliedCopyWith<NotesReply_Applied> get copyWith => _$NotesReply_AppliedCopyWithImpl<NotesReply_Applied>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotesReply_Applied&&const DeepCollectionEquality().equals(other._results, _results));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_results));

@override
String toString() {
  return 'NotesReply.applied(results: $results)';
}


}

/// @nodoc
abstract mixin class $NotesReply_AppliedCopyWith<$Res> implements $NotesReplyCopyWith<$Res> {
  factory $NotesReply_AppliedCopyWith(NotesReply_Applied value, $Res Function(NotesReply_Applied) _then) = _$NotesReply_AppliedCopyWithImpl;
@useResult
$Res call({
 List<NoteOpResult> results
});




}
/// @nodoc
class _$NotesReply_AppliedCopyWithImpl<$Res>
    implements $NotesReply_AppliedCopyWith<$Res> {
  _$NotesReply_AppliedCopyWithImpl(this._self, this._then);

  final NotesReply_Applied _self;
  final $Res Function(NotesReply_Applied) _then;

/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? results = null,}) {
  return _then(NotesReply_Applied(
results: null == results ? _self._results : results // ignore: cast_nullable_to_non_nullable
as List<NoteOpResult>,
  ));
}


}

/// @nodoc


class NotesReply_Failed extends NotesReply {
  const NotesReply_Failed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotesReply_FailedCopyWith<NotesReply_Failed> get copyWith => _$NotesReply_FailedCopyWithImpl<NotesReply_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotesReply_Failed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'NotesReply.failed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $NotesReply_FailedCopyWith<$Res> implements $NotesReplyCopyWith<$Res> {
  factory $NotesReply_FailedCopyWith(NotesReply_Failed value, $Res Function(NotesReply_Failed) _then) = _$NotesReply_FailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$NotesReply_FailedCopyWithImpl<$Res>
    implements $NotesReply_FailedCopyWith<$Res> {
  _$NotesReply_FailedCopyWithImpl(this._self, this._then);

  final NotesReply_Failed _self;
  final $Res Function(NotesReply_Failed) _then;

/// Create a copy of NotesReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(NotesReply_Failed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
