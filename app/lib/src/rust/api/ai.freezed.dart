// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ai.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AiChatEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiChatEvent()';
}


}

/// @nodoc
class $AiChatEventCopyWith<$Res>  {
$AiChatEventCopyWith(AiChatEvent _, $Res Function(AiChatEvent) __);
}


/// Adds pattern-matching-related methods to [AiChatEvent].
extension AiChatEventPatterns on AiChatEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AiChatEvent_AssistantToken value)?  assistantToken,TResult Function( AiChatEvent_Thinking value)?  thinking,TResult Function( AiChatEvent_AssistantMessage value)?  assistantMessage,TResult Function( AiChatEvent_ToolStarted value)?  toolStarted,TResult Function( AiChatEvent_ToolFinished value)?  toolFinished,TResult Function( AiChatEvent_DraftReady value)?  draftReady,TResult Function( AiChatEvent_TurnDone value)?  turnDone,TResult Function( AiChatEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AiChatEvent_AssistantToken() when assistantToken != null:
return assistantToken(_that);case AiChatEvent_Thinking() when thinking != null:
return thinking(_that);case AiChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that);case AiChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that);case AiChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that);case AiChatEvent_DraftReady() when draftReady != null:
return draftReady(_that);case AiChatEvent_TurnDone() when turnDone != null:
return turnDone(_that);case AiChatEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AiChatEvent_AssistantToken value)  assistantToken,required TResult Function( AiChatEvent_Thinking value)  thinking,required TResult Function( AiChatEvent_AssistantMessage value)  assistantMessage,required TResult Function( AiChatEvent_ToolStarted value)  toolStarted,required TResult Function( AiChatEvent_ToolFinished value)  toolFinished,required TResult Function( AiChatEvent_DraftReady value)  draftReady,required TResult Function( AiChatEvent_TurnDone value)  turnDone,required TResult Function( AiChatEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case AiChatEvent_AssistantToken():
return assistantToken(_that);case AiChatEvent_Thinking():
return thinking(_that);case AiChatEvent_AssistantMessage():
return assistantMessage(_that);case AiChatEvent_ToolStarted():
return toolStarted(_that);case AiChatEvent_ToolFinished():
return toolFinished(_that);case AiChatEvent_DraftReady():
return draftReady(_that);case AiChatEvent_TurnDone():
return turnDone(_that);case AiChatEvent_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AiChatEvent_AssistantToken value)?  assistantToken,TResult? Function( AiChatEvent_Thinking value)?  thinking,TResult? Function( AiChatEvent_AssistantMessage value)?  assistantMessage,TResult? Function( AiChatEvent_ToolStarted value)?  toolStarted,TResult? Function( AiChatEvent_ToolFinished value)?  toolFinished,TResult? Function( AiChatEvent_DraftReady value)?  draftReady,TResult? Function( AiChatEvent_TurnDone value)?  turnDone,TResult? Function( AiChatEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case AiChatEvent_AssistantToken() when assistantToken != null:
return assistantToken(_that);case AiChatEvent_Thinking() when thinking != null:
return thinking(_that);case AiChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that);case AiChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that);case AiChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that);case AiChatEvent_DraftReady() when draftReady != null:
return draftReady(_that);case AiChatEvent_TurnDone() when turnDone != null:
return turnDone(_that);case AiChatEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String delta)?  assistantToken,TResult Function()?  thinking,TResult Function( String text)?  assistantMessage,TResult Function( String name,  String summary)?  toolStarted,TResult Function( String name,  bool ok,  String summary)?  toolFinished,TResult Function( AiActionDraft draft)?  draftReady,TResult Function()?  turnDone,TResult Function( String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AiChatEvent_AssistantToken() when assistantToken != null:
return assistantToken(_that.delta);case AiChatEvent_Thinking() when thinking != null:
return thinking();case AiChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that.text);case AiChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that.name,_that.summary);case AiChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that.name,_that.ok,_that.summary);case AiChatEvent_DraftReady() when draftReady != null:
return draftReady(_that.draft);case AiChatEvent_TurnDone() when turnDone != null:
return turnDone();case AiChatEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String delta)  assistantToken,required TResult Function()  thinking,required TResult Function( String text)  assistantMessage,required TResult Function( String name,  String summary)  toolStarted,required TResult Function( String name,  bool ok,  String summary)  toolFinished,required TResult Function( AiActionDraft draft)  draftReady,required TResult Function()  turnDone,required TResult Function( String detail)  failed,}) {final _that = this;
switch (_that) {
case AiChatEvent_AssistantToken():
return assistantToken(_that.delta);case AiChatEvent_Thinking():
return thinking();case AiChatEvent_AssistantMessage():
return assistantMessage(_that.text);case AiChatEvent_ToolStarted():
return toolStarted(_that.name,_that.summary);case AiChatEvent_ToolFinished():
return toolFinished(_that.name,_that.ok,_that.summary);case AiChatEvent_DraftReady():
return draftReady(_that.draft);case AiChatEvent_TurnDone():
return turnDone();case AiChatEvent_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String delta)?  assistantToken,TResult? Function()?  thinking,TResult? Function( String text)?  assistantMessage,TResult? Function( String name,  String summary)?  toolStarted,TResult? Function( String name,  bool ok,  String summary)?  toolFinished,TResult? Function( AiActionDraft draft)?  draftReady,TResult? Function()?  turnDone,TResult? Function( String detail)?  failed,}) {final _that = this;
switch (_that) {
case AiChatEvent_AssistantToken() when assistantToken != null:
return assistantToken(_that.delta);case AiChatEvent_Thinking() when thinking != null:
return thinking();case AiChatEvent_AssistantMessage() when assistantMessage != null:
return assistantMessage(_that.text);case AiChatEvent_ToolStarted() when toolStarted != null:
return toolStarted(_that.name,_that.summary);case AiChatEvent_ToolFinished() when toolFinished != null:
return toolFinished(_that.name,_that.ok,_that.summary);case AiChatEvent_DraftReady() when draftReady != null:
return draftReady(_that.draft);case AiChatEvent_TurnDone() when turnDone != null:
return turnDone();case AiChatEvent_Failed() when failed != null:
return failed(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class AiChatEvent_AssistantToken extends AiChatEvent {
  const AiChatEvent_AssistantToken({required this.delta}): super._();
  

 final  String delta;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiChatEvent_AssistantTokenCopyWith<AiChatEvent_AssistantToken> get copyWith => _$AiChatEvent_AssistantTokenCopyWithImpl<AiChatEvent_AssistantToken>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_AssistantToken&&(identical(other.delta, delta) || other.delta == delta));
}


@override
int get hashCode => Object.hash(runtimeType,delta);

@override
String toString() {
  return 'AiChatEvent.assistantToken(delta: $delta)';
}


}

/// @nodoc
abstract mixin class $AiChatEvent_AssistantTokenCopyWith<$Res> implements $AiChatEventCopyWith<$Res> {
  factory $AiChatEvent_AssistantTokenCopyWith(AiChatEvent_AssistantToken value, $Res Function(AiChatEvent_AssistantToken) _then) = _$AiChatEvent_AssistantTokenCopyWithImpl;
@useResult
$Res call({
 String delta
});




}
/// @nodoc
class _$AiChatEvent_AssistantTokenCopyWithImpl<$Res>
    implements $AiChatEvent_AssistantTokenCopyWith<$Res> {
  _$AiChatEvent_AssistantTokenCopyWithImpl(this._self, this._then);

  final AiChatEvent_AssistantToken _self;
  final $Res Function(AiChatEvent_AssistantToken) _then;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? delta = null,}) {
  return _then(AiChatEvent_AssistantToken(
delta: null == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiChatEvent_Thinking extends AiChatEvent {
  const AiChatEvent_Thinking(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_Thinking);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiChatEvent.thinking()';
}


}




/// @nodoc


class AiChatEvent_AssistantMessage extends AiChatEvent {
  const AiChatEvent_AssistantMessage({required this.text}): super._();
  

 final  String text;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiChatEvent_AssistantMessageCopyWith<AiChatEvent_AssistantMessage> get copyWith => _$AiChatEvent_AssistantMessageCopyWithImpl<AiChatEvent_AssistantMessage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_AssistantMessage&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'AiChatEvent.assistantMessage(text: $text)';
}


}

/// @nodoc
abstract mixin class $AiChatEvent_AssistantMessageCopyWith<$Res> implements $AiChatEventCopyWith<$Res> {
  factory $AiChatEvent_AssistantMessageCopyWith(AiChatEvent_AssistantMessage value, $Res Function(AiChatEvent_AssistantMessage) _then) = _$AiChatEvent_AssistantMessageCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AiChatEvent_AssistantMessageCopyWithImpl<$Res>
    implements $AiChatEvent_AssistantMessageCopyWith<$Res> {
  _$AiChatEvent_AssistantMessageCopyWithImpl(this._self, this._then);

  final AiChatEvent_AssistantMessage _self;
  final $Res Function(AiChatEvent_AssistantMessage) _then;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AiChatEvent_AssistantMessage(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiChatEvent_ToolStarted extends AiChatEvent {
  const AiChatEvent_ToolStarted({required this.name, required this.summary}): super._();
  

 final  String name;
 final  String summary;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiChatEvent_ToolStartedCopyWith<AiChatEvent_ToolStarted> get copyWith => _$AiChatEvent_ToolStartedCopyWithImpl<AiChatEvent_ToolStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_ToolStarted&&(identical(other.name, name) || other.name == name)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode => Object.hash(runtimeType,name,summary);

@override
String toString() {
  return 'AiChatEvent.toolStarted(name: $name, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $AiChatEvent_ToolStartedCopyWith<$Res> implements $AiChatEventCopyWith<$Res> {
  factory $AiChatEvent_ToolStartedCopyWith(AiChatEvent_ToolStarted value, $Res Function(AiChatEvent_ToolStarted) _then) = _$AiChatEvent_ToolStartedCopyWithImpl;
@useResult
$Res call({
 String name, String summary
});




}
/// @nodoc
class _$AiChatEvent_ToolStartedCopyWithImpl<$Res>
    implements $AiChatEvent_ToolStartedCopyWith<$Res> {
  _$AiChatEvent_ToolStartedCopyWithImpl(this._self, this._then);

  final AiChatEvent_ToolStarted _self;
  final $Res Function(AiChatEvent_ToolStarted) _then;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? summary = null,}) {
  return _then(AiChatEvent_ToolStarted(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiChatEvent_ToolFinished extends AiChatEvent {
  const AiChatEvent_ToolFinished({required this.name, required this.ok, required this.summary}): super._();
  

 final  String name;
 final  bool ok;
 final  String summary;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiChatEvent_ToolFinishedCopyWith<AiChatEvent_ToolFinished> get copyWith => _$AiChatEvent_ToolFinishedCopyWithImpl<AiChatEvent_ToolFinished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_ToolFinished&&(identical(other.name, name) || other.name == name)&&(identical(other.ok, ok) || other.ok == ok)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode => Object.hash(runtimeType,name,ok,summary);

@override
String toString() {
  return 'AiChatEvent.toolFinished(name: $name, ok: $ok, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $AiChatEvent_ToolFinishedCopyWith<$Res> implements $AiChatEventCopyWith<$Res> {
  factory $AiChatEvent_ToolFinishedCopyWith(AiChatEvent_ToolFinished value, $Res Function(AiChatEvent_ToolFinished) _then) = _$AiChatEvent_ToolFinishedCopyWithImpl;
@useResult
$Res call({
 String name, bool ok, String summary
});




}
/// @nodoc
class _$AiChatEvent_ToolFinishedCopyWithImpl<$Res>
    implements $AiChatEvent_ToolFinishedCopyWith<$Res> {
  _$AiChatEvent_ToolFinishedCopyWithImpl(this._self, this._then);

  final AiChatEvent_ToolFinished _self;
  final $Res Function(AiChatEvent_ToolFinished) _then;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? ok = null,Object? summary = null,}) {
  return _then(AiChatEvent_ToolFinished(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiChatEvent_DraftReady extends AiChatEvent {
  const AiChatEvent_DraftReady({required this.draft}): super._();
  

 final  AiActionDraft draft;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiChatEvent_DraftReadyCopyWith<AiChatEvent_DraftReady> get copyWith => _$AiChatEvent_DraftReadyCopyWithImpl<AiChatEvent_DraftReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_DraftReady&&(identical(other.draft, draft) || other.draft == draft));
}


@override
int get hashCode => Object.hash(runtimeType,draft);

@override
String toString() {
  return 'AiChatEvent.draftReady(draft: $draft)';
}


}

/// @nodoc
abstract mixin class $AiChatEvent_DraftReadyCopyWith<$Res> implements $AiChatEventCopyWith<$Res> {
  factory $AiChatEvent_DraftReadyCopyWith(AiChatEvent_DraftReady value, $Res Function(AiChatEvent_DraftReady) _then) = _$AiChatEvent_DraftReadyCopyWithImpl;
@useResult
$Res call({
 AiActionDraft draft
});




}
/// @nodoc
class _$AiChatEvent_DraftReadyCopyWithImpl<$Res>
    implements $AiChatEvent_DraftReadyCopyWith<$Res> {
  _$AiChatEvent_DraftReadyCopyWithImpl(this._self, this._then);

  final AiChatEvent_DraftReady _self;
  final $Res Function(AiChatEvent_DraftReady) _then;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? draft = null,}) {
  return _then(AiChatEvent_DraftReady(
draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as AiActionDraft,
  ));
}


}

/// @nodoc


class AiChatEvent_TurnDone extends AiChatEvent {
  const AiChatEvent_TurnDone(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_TurnDone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiChatEvent.turnDone()';
}


}




/// @nodoc


class AiChatEvent_Failed extends AiChatEvent {
  const AiChatEvent_Failed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiChatEvent_FailedCopyWith<AiChatEvent_Failed> get copyWith => _$AiChatEvent_FailedCopyWithImpl<AiChatEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiChatEvent_Failed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'AiChatEvent.failed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $AiChatEvent_FailedCopyWith<$Res> implements $AiChatEventCopyWith<$Res> {
  factory $AiChatEvent_FailedCopyWith(AiChatEvent_Failed value, $Res Function(AiChatEvent_Failed) _then) = _$AiChatEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$AiChatEvent_FailedCopyWithImpl<$Res>
    implements $AiChatEvent_FailedCopyWith<$Res> {
  _$AiChatEvent_FailedCopyWithImpl(this._self, this._then);

  final AiChatEvent_Failed _self;
  final $Res Function(AiChatEvent_Failed) _then;

/// Create a copy of AiChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(AiChatEvent_Failed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AiSetupEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiSetupEvent()';
}


}

/// @nodoc
class $AiSetupEventCopyWith<$Res>  {
$AiSetupEventCopyWith(AiSetupEvent _, $Res Function(AiSetupEvent) __);
}


/// Adds pattern-matching-related methods to [AiSetupEvent].
extension AiSetupEventPatterns on AiSetupEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AiSetupEvent_Probing value)?  probing,TResult Function( AiSetupEvent_Downloading value)?  downloading,TResult Function( AiSetupEvent_Verifying value)?  verifying,TResult Function( AiSetupEvent_Extracting value)?  extracting,TResult Function( AiSetupEvent_StartingServer value)?  startingServer,TResult Function( AiSetupEvent_Ready value)?  ready,TResult Function( AiSetupEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AiSetupEvent_Probing() when probing != null:
return probing(_that);case AiSetupEvent_Downloading() when downloading != null:
return downloading(_that);case AiSetupEvent_Verifying() when verifying != null:
return verifying(_that);case AiSetupEvent_Extracting() when extracting != null:
return extracting(_that);case AiSetupEvent_StartingServer() when startingServer != null:
return startingServer(_that);case AiSetupEvent_Ready() when ready != null:
return ready(_that);case AiSetupEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AiSetupEvent_Probing value)  probing,required TResult Function( AiSetupEvent_Downloading value)  downloading,required TResult Function( AiSetupEvent_Verifying value)  verifying,required TResult Function( AiSetupEvent_Extracting value)  extracting,required TResult Function( AiSetupEvent_StartingServer value)  startingServer,required TResult Function( AiSetupEvent_Ready value)  ready,required TResult Function( AiSetupEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case AiSetupEvent_Probing():
return probing(_that);case AiSetupEvent_Downloading():
return downloading(_that);case AiSetupEvent_Verifying():
return verifying(_that);case AiSetupEvent_Extracting():
return extracting(_that);case AiSetupEvent_StartingServer():
return startingServer(_that);case AiSetupEvent_Ready():
return ready(_that);case AiSetupEvent_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AiSetupEvent_Probing value)?  probing,TResult? Function( AiSetupEvent_Downloading value)?  downloading,TResult? Function( AiSetupEvent_Verifying value)?  verifying,TResult? Function( AiSetupEvent_Extracting value)?  extracting,TResult? Function( AiSetupEvent_StartingServer value)?  startingServer,TResult? Function( AiSetupEvent_Ready value)?  ready,TResult? Function( AiSetupEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case AiSetupEvent_Probing() when probing != null:
return probing(_that);case AiSetupEvent_Downloading() when downloading != null:
return downloading(_that);case AiSetupEvent_Verifying() when verifying != null:
return verifying(_that);case AiSetupEvent_Extracting() when extracting != null:
return extracting(_that);case AiSetupEvent_StartingServer() when startingServer != null:
return startingServer(_that);case AiSetupEvent_Ready() when ready != null:
return ready(_that);case AiSetupEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  probing,TResult Function( String asset,  BigInt downloaded,  BigInt totalBytes,  BigInt bytesPerSec)?  downloading,TResult Function( String asset)?  verifying,TResult Function( String asset)?  extracting,TResult Function()?  startingServer,TResult Function( String modelId,  String backend,  int gpuLayers,  String providerLabel)?  ready,TResult Function( String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AiSetupEvent_Probing() when probing != null:
return probing();case AiSetupEvent_Downloading() when downloading != null:
return downloading(_that.asset,_that.downloaded,_that.totalBytes,_that.bytesPerSec);case AiSetupEvent_Verifying() when verifying != null:
return verifying(_that.asset);case AiSetupEvent_Extracting() when extracting != null:
return extracting(_that.asset);case AiSetupEvent_StartingServer() when startingServer != null:
return startingServer();case AiSetupEvent_Ready() when ready != null:
return ready(_that.modelId,_that.backend,_that.gpuLayers,_that.providerLabel);case AiSetupEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  probing,required TResult Function( String asset,  BigInt downloaded,  BigInt totalBytes,  BigInt bytesPerSec)  downloading,required TResult Function( String asset)  verifying,required TResult Function( String asset)  extracting,required TResult Function()  startingServer,required TResult Function( String modelId,  String backend,  int gpuLayers,  String providerLabel)  ready,required TResult Function( String detail)  failed,}) {final _that = this;
switch (_that) {
case AiSetupEvent_Probing():
return probing();case AiSetupEvent_Downloading():
return downloading(_that.asset,_that.downloaded,_that.totalBytes,_that.bytesPerSec);case AiSetupEvent_Verifying():
return verifying(_that.asset);case AiSetupEvent_Extracting():
return extracting(_that.asset);case AiSetupEvent_StartingServer():
return startingServer();case AiSetupEvent_Ready():
return ready(_that.modelId,_that.backend,_that.gpuLayers,_that.providerLabel);case AiSetupEvent_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  probing,TResult? Function( String asset,  BigInt downloaded,  BigInt totalBytes,  BigInt bytesPerSec)?  downloading,TResult? Function( String asset)?  verifying,TResult? Function( String asset)?  extracting,TResult? Function()?  startingServer,TResult? Function( String modelId,  String backend,  int gpuLayers,  String providerLabel)?  ready,TResult? Function( String detail)?  failed,}) {final _that = this;
switch (_that) {
case AiSetupEvent_Probing() when probing != null:
return probing();case AiSetupEvent_Downloading() when downloading != null:
return downloading(_that.asset,_that.downloaded,_that.totalBytes,_that.bytesPerSec);case AiSetupEvent_Verifying() when verifying != null:
return verifying(_that.asset);case AiSetupEvent_Extracting() when extracting != null:
return extracting(_that.asset);case AiSetupEvent_StartingServer() when startingServer != null:
return startingServer();case AiSetupEvent_Ready() when ready != null:
return ready(_that.modelId,_that.backend,_that.gpuLayers,_that.providerLabel);case AiSetupEvent_Failed() when failed != null:
return failed(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class AiSetupEvent_Probing extends AiSetupEvent {
  const AiSetupEvent_Probing(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_Probing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiSetupEvent.probing()';
}


}




/// @nodoc


class AiSetupEvent_Downloading extends AiSetupEvent {
  const AiSetupEvent_Downloading({required this.asset, required this.downloaded, required this.totalBytes, required this.bytesPerSec}): super._();
  

 final  String asset;
 final  BigInt downloaded;
 final  BigInt totalBytes;
 final  BigInt bytesPerSec;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiSetupEvent_DownloadingCopyWith<AiSetupEvent_Downloading> get copyWith => _$AiSetupEvent_DownloadingCopyWithImpl<AiSetupEvent_Downloading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_Downloading&&(identical(other.asset, asset) || other.asset == asset)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.bytesPerSec, bytesPerSec) || other.bytesPerSec == bytesPerSec));
}


@override
int get hashCode => Object.hash(runtimeType,asset,downloaded,totalBytes,bytesPerSec);

@override
String toString() {
  return 'AiSetupEvent.downloading(asset: $asset, downloaded: $downloaded, totalBytes: $totalBytes, bytesPerSec: $bytesPerSec)';
}


}

/// @nodoc
abstract mixin class $AiSetupEvent_DownloadingCopyWith<$Res> implements $AiSetupEventCopyWith<$Res> {
  factory $AiSetupEvent_DownloadingCopyWith(AiSetupEvent_Downloading value, $Res Function(AiSetupEvent_Downloading) _then) = _$AiSetupEvent_DownloadingCopyWithImpl;
@useResult
$Res call({
 String asset, BigInt downloaded, BigInt totalBytes, BigInt bytesPerSec
});




}
/// @nodoc
class _$AiSetupEvent_DownloadingCopyWithImpl<$Res>
    implements $AiSetupEvent_DownloadingCopyWith<$Res> {
  _$AiSetupEvent_DownloadingCopyWithImpl(this._self, this._then);

  final AiSetupEvent_Downloading _self;
  final $Res Function(AiSetupEvent_Downloading) _then;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? asset = null,Object? downloaded = null,Object? totalBytes = null,Object? bytesPerSec = null,}) {
  return _then(AiSetupEvent_Downloading(
asset: null == asset ? _self.asset : asset // ignore: cast_nullable_to_non_nullable
as String,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as BigInt,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,bytesPerSec: null == bytesPerSec ? _self.bytesPerSec : bytesPerSec // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class AiSetupEvent_Verifying extends AiSetupEvent {
  const AiSetupEvent_Verifying({required this.asset}): super._();
  

 final  String asset;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiSetupEvent_VerifyingCopyWith<AiSetupEvent_Verifying> get copyWith => _$AiSetupEvent_VerifyingCopyWithImpl<AiSetupEvent_Verifying>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_Verifying&&(identical(other.asset, asset) || other.asset == asset));
}


@override
int get hashCode => Object.hash(runtimeType,asset);

@override
String toString() {
  return 'AiSetupEvent.verifying(asset: $asset)';
}


}

/// @nodoc
abstract mixin class $AiSetupEvent_VerifyingCopyWith<$Res> implements $AiSetupEventCopyWith<$Res> {
  factory $AiSetupEvent_VerifyingCopyWith(AiSetupEvent_Verifying value, $Res Function(AiSetupEvent_Verifying) _then) = _$AiSetupEvent_VerifyingCopyWithImpl;
@useResult
$Res call({
 String asset
});




}
/// @nodoc
class _$AiSetupEvent_VerifyingCopyWithImpl<$Res>
    implements $AiSetupEvent_VerifyingCopyWith<$Res> {
  _$AiSetupEvent_VerifyingCopyWithImpl(this._self, this._then);

  final AiSetupEvent_Verifying _self;
  final $Res Function(AiSetupEvent_Verifying) _then;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? asset = null,}) {
  return _then(AiSetupEvent_Verifying(
asset: null == asset ? _self.asset : asset // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiSetupEvent_Extracting extends AiSetupEvent {
  const AiSetupEvent_Extracting({required this.asset}): super._();
  

 final  String asset;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiSetupEvent_ExtractingCopyWith<AiSetupEvent_Extracting> get copyWith => _$AiSetupEvent_ExtractingCopyWithImpl<AiSetupEvent_Extracting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_Extracting&&(identical(other.asset, asset) || other.asset == asset));
}


@override
int get hashCode => Object.hash(runtimeType,asset);

@override
String toString() {
  return 'AiSetupEvent.extracting(asset: $asset)';
}


}

/// @nodoc
abstract mixin class $AiSetupEvent_ExtractingCopyWith<$Res> implements $AiSetupEventCopyWith<$Res> {
  factory $AiSetupEvent_ExtractingCopyWith(AiSetupEvent_Extracting value, $Res Function(AiSetupEvent_Extracting) _then) = _$AiSetupEvent_ExtractingCopyWithImpl;
@useResult
$Res call({
 String asset
});




}
/// @nodoc
class _$AiSetupEvent_ExtractingCopyWithImpl<$Res>
    implements $AiSetupEvent_ExtractingCopyWith<$Res> {
  _$AiSetupEvent_ExtractingCopyWithImpl(this._self, this._then);

  final AiSetupEvent_Extracting _self;
  final $Res Function(AiSetupEvent_Extracting) _then;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? asset = null,}) {
  return _then(AiSetupEvent_Extracting(
asset: null == asset ? _self.asset : asset // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiSetupEvent_StartingServer extends AiSetupEvent {
  const AiSetupEvent_StartingServer(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_StartingServer);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiSetupEvent.startingServer()';
}


}




/// @nodoc


class AiSetupEvent_Ready extends AiSetupEvent {
  const AiSetupEvent_Ready({required this.modelId, required this.backend, required this.gpuLayers, required this.providerLabel}): super._();
  

 final  String modelId;
 final  String backend;
 final  int gpuLayers;
 final  String providerLabel;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiSetupEvent_ReadyCopyWith<AiSetupEvent_Ready> get copyWith => _$AiSetupEvent_ReadyCopyWithImpl<AiSetupEvent_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_Ready&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.backend, backend) || other.backend == backend)&&(identical(other.gpuLayers, gpuLayers) || other.gpuLayers == gpuLayers)&&(identical(other.providerLabel, providerLabel) || other.providerLabel == providerLabel));
}


@override
int get hashCode => Object.hash(runtimeType,modelId,backend,gpuLayers,providerLabel);

@override
String toString() {
  return 'AiSetupEvent.ready(modelId: $modelId, backend: $backend, gpuLayers: $gpuLayers, providerLabel: $providerLabel)';
}


}

/// @nodoc
abstract mixin class $AiSetupEvent_ReadyCopyWith<$Res> implements $AiSetupEventCopyWith<$Res> {
  factory $AiSetupEvent_ReadyCopyWith(AiSetupEvent_Ready value, $Res Function(AiSetupEvent_Ready) _then) = _$AiSetupEvent_ReadyCopyWithImpl;
@useResult
$Res call({
 String modelId, String backend, int gpuLayers, String providerLabel
});




}
/// @nodoc
class _$AiSetupEvent_ReadyCopyWithImpl<$Res>
    implements $AiSetupEvent_ReadyCopyWith<$Res> {
  _$AiSetupEvent_ReadyCopyWithImpl(this._self, this._then);

  final AiSetupEvent_Ready _self;
  final $Res Function(AiSetupEvent_Ready) _then;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? backend = null,Object? gpuLayers = null,Object? providerLabel = null,}) {
  return _then(AiSetupEvent_Ready(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,backend: null == backend ? _self.backend : backend // ignore: cast_nullable_to_non_nullable
as String,gpuLayers: null == gpuLayers ? _self.gpuLayers : gpuLayers // ignore: cast_nullable_to_non_nullable
as int,providerLabel: null == providerLabel ? _self.providerLabel : providerLabel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiSetupEvent_Failed extends AiSetupEvent {
  const AiSetupEvent_Failed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiSetupEvent_FailedCopyWith<AiSetupEvent_Failed> get copyWith => _$AiSetupEvent_FailedCopyWithImpl<AiSetupEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiSetupEvent_Failed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'AiSetupEvent.failed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $AiSetupEvent_FailedCopyWith<$Res> implements $AiSetupEventCopyWith<$Res> {
  factory $AiSetupEvent_FailedCopyWith(AiSetupEvent_Failed value, $Res Function(AiSetupEvent_Failed) _then) = _$AiSetupEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$AiSetupEvent_FailedCopyWithImpl<$Res>
    implements $AiSetupEvent_FailedCopyWith<$Res> {
  _$AiSetupEvent_FailedCopyWithImpl(this._self, this._then);

  final AiSetupEvent_Failed _self;
  final $Res Function(AiSetupEvent_Failed) _then;

/// Create a copy of AiSetupEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(AiSetupEvent_Failed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
