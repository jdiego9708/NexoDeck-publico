// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'control.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ControlEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlEvent()';
}


}

/// @nodoc
class $ControlEventCopyWith<$Res>  {
$ControlEventCopyWith(ControlEvent _, $Res Function(ControlEvent) __);
}


/// Adds pattern-matching-related methods to [ControlEvent].
extension ControlEventPatterns on ControlEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ControlEvent_Started value)?  started,TResult Function( ControlEvent_Stopped value)?  stopped,TResult Function( ControlEvent_ToolCalled value)?  toolCalled,TResult Function( ControlEvent_Rejected value)?  rejected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ControlEvent_Started() when started != null:
return started(_that);case ControlEvent_Stopped() when stopped != null:
return stopped(_that);case ControlEvent_ToolCalled() when toolCalled != null:
return toolCalled(_that);case ControlEvent_Rejected() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ControlEvent_Started value)  started,required TResult Function( ControlEvent_Stopped value)  stopped,required TResult Function( ControlEvent_ToolCalled value)  toolCalled,required TResult Function( ControlEvent_Rejected value)  rejected,}){
final _that = this;
switch (_that) {
case ControlEvent_Started():
return started(_that);case ControlEvent_Stopped():
return stopped(_that);case ControlEvent_ToolCalled():
return toolCalled(_that);case ControlEvent_Rejected():
return rejected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ControlEvent_Started value)?  started,TResult? Function( ControlEvent_Stopped value)?  stopped,TResult? Function( ControlEvent_ToolCalled value)?  toolCalled,TResult? Function( ControlEvent_Rejected value)?  rejected,}){
final _that = this;
switch (_that) {
case ControlEvent_Started() when started != null:
return started(_that);case ControlEvent_Stopped() when stopped != null:
return stopped(_that);case ControlEvent_ToolCalled() when toolCalled != null:
return toolCalled(_that);case ControlEvent_Rejected() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int port)?  started,TResult Function()?  stopped,TResult Function( String tool,  String summary,  bool ok)?  toolCalled,TResult Function( String reason)?  rejected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ControlEvent_Started() when started != null:
return started(_that.port);case ControlEvent_Stopped() when stopped != null:
return stopped();case ControlEvent_ToolCalled() when toolCalled != null:
return toolCalled(_that.tool,_that.summary,_that.ok);case ControlEvent_Rejected() when rejected != null:
return rejected(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int port)  started,required TResult Function()  stopped,required TResult Function( String tool,  String summary,  bool ok)  toolCalled,required TResult Function( String reason)  rejected,}) {final _that = this;
switch (_that) {
case ControlEvent_Started():
return started(_that.port);case ControlEvent_Stopped():
return stopped();case ControlEvent_ToolCalled():
return toolCalled(_that.tool,_that.summary,_that.ok);case ControlEvent_Rejected():
return rejected(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int port)?  started,TResult? Function()?  stopped,TResult? Function( String tool,  String summary,  bool ok)?  toolCalled,TResult? Function( String reason)?  rejected,}) {final _that = this;
switch (_that) {
case ControlEvent_Started() when started != null:
return started(_that.port);case ControlEvent_Stopped() when stopped != null:
return stopped();case ControlEvent_ToolCalled() when toolCalled != null:
return toolCalled(_that.tool,_that.summary,_that.ok);case ControlEvent_Rejected() when rejected != null:
return rejected(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ControlEvent_Started extends ControlEvent {
  const ControlEvent_Started({required this.port}): super._();
  

 final  int port;

/// Create a copy of ControlEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlEvent_StartedCopyWith<ControlEvent_Started> get copyWith => _$ControlEvent_StartedCopyWithImpl<ControlEvent_Started>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlEvent_Started&&(identical(other.port, port) || other.port == port));
}


@override
int get hashCode => Object.hash(runtimeType,port);

@override
String toString() {
  return 'ControlEvent.started(port: $port)';
}


}

/// @nodoc
abstract mixin class $ControlEvent_StartedCopyWith<$Res> implements $ControlEventCopyWith<$Res> {
  factory $ControlEvent_StartedCopyWith(ControlEvent_Started value, $Res Function(ControlEvent_Started) _then) = _$ControlEvent_StartedCopyWithImpl;
@useResult
$Res call({
 int port
});




}
/// @nodoc
class _$ControlEvent_StartedCopyWithImpl<$Res>
    implements $ControlEvent_StartedCopyWith<$Res> {
  _$ControlEvent_StartedCopyWithImpl(this._self, this._then);

  final ControlEvent_Started _self;
  final $Res Function(ControlEvent_Started) _then;

/// Create a copy of ControlEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? port = null,}) {
  return _then(ControlEvent_Started(
port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ControlEvent_Stopped extends ControlEvent {
  const ControlEvent_Stopped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlEvent_Stopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlEvent.stopped()';
}


}




/// @nodoc


class ControlEvent_ToolCalled extends ControlEvent {
  const ControlEvent_ToolCalled({required this.tool, required this.summary, required this.ok}): super._();
  

 final  String tool;
 final  String summary;
 final  bool ok;

/// Create a copy of ControlEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlEvent_ToolCalledCopyWith<ControlEvent_ToolCalled> get copyWith => _$ControlEvent_ToolCalledCopyWithImpl<ControlEvent_ToolCalled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlEvent_ToolCalled&&(identical(other.tool, tool) || other.tool == tool)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.ok, ok) || other.ok == ok));
}


@override
int get hashCode => Object.hash(runtimeType,tool,summary,ok);

@override
String toString() {
  return 'ControlEvent.toolCalled(tool: $tool, summary: $summary, ok: $ok)';
}


}

/// @nodoc
abstract mixin class $ControlEvent_ToolCalledCopyWith<$Res> implements $ControlEventCopyWith<$Res> {
  factory $ControlEvent_ToolCalledCopyWith(ControlEvent_ToolCalled value, $Res Function(ControlEvent_ToolCalled) _then) = _$ControlEvent_ToolCalledCopyWithImpl;
@useResult
$Res call({
 String tool, String summary, bool ok
});




}
/// @nodoc
class _$ControlEvent_ToolCalledCopyWithImpl<$Res>
    implements $ControlEvent_ToolCalledCopyWith<$Res> {
  _$ControlEvent_ToolCalledCopyWithImpl(this._self, this._then);

  final ControlEvent_ToolCalled _self;
  final $Res Function(ControlEvent_ToolCalled) _then;

/// Create a copy of ControlEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? tool = null,Object? summary = null,Object? ok = null,}) {
  return _then(ControlEvent_ToolCalled(
tool: null == tool ? _self.tool : tool // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ControlEvent_Rejected extends ControlEvent {
  const ControlEvent_Rejected({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ControlEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ControlEvent_RejectedCopyWith<ControlEvent_Rejected> get copyWith => _$ControlEvent_RejectedCopyWithImpl<ControlEvent_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlEvent_Rejected&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'ControlEvent.rejected(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ControlEvent_RejectedCopyWith<$Res> implements $ControlEventCopyWith<$Res> {
  factory $ControlEvent_RejectedCopyWith(ControlEvent_Rejected value, $Res Function(ControlEvent_Rejected) _then) = _$ControlEvent_RejectedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ControlEvent_RejectedCopyWithImpl<$Res>
    implements $ControlEvent_RejectedCopyWith<$Res> {
  _$ControlEvent_RejectedCopyWithImpl(this._self, this._then);

  final ControlEvent_Rejected _self;
  final $Res Function(ControlEvent_Rejected) _then;

/// Create a copy of ControlEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ControlEvent_Rejected(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CorrespondentEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CorrespondentEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CorrespondentEvent()';
}


}

/// @nodoc
class $CorrespondentEventCopyWith<$Res>  {
$CorrespondentEventCopyWith(CorrespondentEvent _, $Res Function(CorrespondentEvent) __);
}


/// Adds pattern-matching-related methods to [CorrespondentEvent].
extension CorrespondentEventPatterns on CorrespondentEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CorrespondentEvent_Delivered value)?  delivered,TResult Function( CorrespondentEvent_Replied value)?  replied,TResult Function( CorrespondentEvent_Posted value)?  posted,TResult Function( CorrespondentEvent_TimedOut value)?  timedOut,TResult Function( CorrespondentEvent_SessionsChanged value)?  sessionsChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CorrespondentEvent_Delivered() when delivered != null:
return delivered(_that);case CorrespondentEvent_Replied() when replied != null:
return replied(_that);case CorrespondentEvent_Posted() when posted != null:
return posted(_that);case CorrespondentEvent_TimedOut() when timedOut != null:
return timedOut(_that);case CorrespondentEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CorrespondentEvent_Delivered value)  delivered,required TResult Function( CorrespondentEvent_Replied value)  replied,required TResult Function( CorrespondentEvent_Posted value)  posted,required TResult Function( CorrespondentEvent_TimedOut value)  timedOut,required TResult Function( CorrespondentEvent_SessionsChanged value)  sessionsChanged,}){
final _that = this;
switch (_that) {
case CorrespondentEvent_Delivered():
return delivered(_that);case CorrespondentEvent_Replied():
return replied(_that);case CorrespondentEvent_Posted():
return posted(_that);case CorrespondentEvent_TimedOut():
return timedOut(_that);case CorrespondentEvent_SessionsChanged():
return sessionsChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CorrespondentEvent_Delivered value)?  delivered,TResult? Function( CorrespondentEvent_Replied value)?  replied,TResult? Function( CorrespondentEvent_Posted value)?  posted,TResult? Function( CorrespondentEvent_TimedOut value)?  timedOut,TResult? Function( CorrespondentEvent_SessionsChanged value)?  sessionsChanged,}){
final _that = this;
switch (_that) {
case CorrespondentEvent_Delivered() when delivered != null:
return delivered(_that);case CorrespondentEvent_Replied() when replied != null:
return replied(_that);case CorrespondentEvent_Posted() when posted != null:
return posted(_that);case CorrespondentEvent_TimedOut() when timedOut != null:
return timedOut(_that);case CorrespondentEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String session)?  delivered,TResult Function( String id,  String text)?  replied,TResult Function( String text,  String? from)?  posted,TResult Function( String id,  String reason)?  timedOut,TResult Function()?  sessionsChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CorrespondentEvent_Delivered() when delivered != null:
return delivered(_that.id,_that.session);case CorrespondentEvent_Replied() when replied != null:
return replied(_that.id,_that.text);case CorrespondentEvent_Posted() when posted != null:
return posted(_that.text,_that.from);case CorrespondentEvent_TimedOut() when timedOut != null:
return timedOut(_that.id,_that.reason);case CorrespondentEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String session)  delivered,required TResult Function( String id,  String text)  replied,required TResult Function( String text,  String? from)  posted,required TResult Function( String id,  String reason)  timedOut,required TResult Function()  sessionsChanged,}) {final _that = this;
switch (_that) {
case CorrespondentEvent_Delivered():
return delivered(_that.id,_that.session);case CorrespondentEvent_Replied():
return replied(_that.id,_that.text);case CorrespondentEvent_Posted():
return posted(_that.text,_that.from);case CorrespondentEvent_TimedOut():
return timedOut(_that.id,_that.reason);case CorrespondentEvent_SessionsChanged():
return sessionsChanged();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String session)?  delivered,TResult? Function( String id,  String text)?  replied,TResult? Function( String text,  String? from)?  posted,TResult? Function( String id,  String reason)?  timedOut,TResult? Function()?  sessionsChanged,}) {final _that = this;
switch (_that) {
case CorrespondentEvent_Delivered() when delivered != null:
return delivered(_that.id,_that.session);case CorrespondentEvent_Replied() when replied != null:
return replied(_that.id,_that.text);case CorrespondentEvent_Posted() when posted != null:
return posted(_that.text,_that.from);case CorrespondentEvent_TimedOut() when timedOut != null:
return timedOut(_that.id,_that.reason);case CorrespondentEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged();case _:
  return null;

}
}

}

/// @nodoc


class CorrespondentEvent_Delivered extends CorrespondentEvent {
  const CorrespondentEvent_Delivered({required this.id, required this.session}): super._();
  

 final  String id;
 final  String session;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CorrespondentEvent_DeliveredCopyWith<CorrespondentEvent_Delivered> get copyWith => _$CorrespondentEvent_DeliveredCopyWithImpl<CorrespondentEvent_Delivered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CorrespondentEvent_Delivered&&(identical(other.id, id) || other.id == id)&&(identical(other.session, session) || other.session == session));
}


@override
int get hashCode => Object.hash(runtimeType,id,session);

@override
String toString() {
  return 'CorrespondentEvent.delivered(id: $id, session: $session)';
}


}

/// @nodoc
abstract mixin class $CorrespondentEvent_DeliveredCopyWith<$Res> implements $CorrespondentEventCopyWith<$Res> {
  factory $CorrespondentEvent_DeliveredCopyWith(CorrespondentEvent_Delivered value, $Res Function(CorrespondentEvent_Delivered) _then) = _$CorrespondentEvent_DeliveredCopyWithImpl;
@useResult
$Res call({
 String id, String session
});




}
/// @nodoc
class _$CorrespondentEvent_DeliveredCopyWithImpl<$Res>
    implements $CorrespondentEvent_DeliveredCopyWith<$Res> {
  _$CorrespondentEvent_DeliveredCopyWithImpl(this._self, this._then);

  final CorrespondentEvent_Delivered _self;
  final $Res Function(CorrespondentEvent_Delivered) _then;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? session = null,}) {
  return _then(CorrespondentEvent_Delivered(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CorrespondentEvent_Replied extends CorrespondentEvent {
  const CorrespondentEvent_Replied({required this.id, required this.text}): super._();
  

 final  String id;
 final  String text;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CorrespondentEvent_RepliedCopyWith<CorrespondentEvent_Replied> get copyWith => _$CorrespondentEvent_RepliedCopyWithImpl<CorrespondentEvent_Replied>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CorrespondentEvent_Replied&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,id,text);

@override
String toString() {
  return 'CorrespondentEvent.replied(id: $id, text: $text)';
}


}

/// @nodoc
abstract mixin class $CorrespondentEvent_RepliedCopyWith<$Res> implements $CorrespondentEventCopyWith<$Res> {
  factory $CorrespondentEvent_RepliedCopyWith(CorrespondentEvent_Replied value, $Res Function(CorrespondentEvent_Replied) _then) = _$CorrespondentEvent_RepliedCopyWithImpl;
@useResult
$Res call({
 String id, String text
});




}
/// @nodoc
class _$CorrespondentEvent_RepliedCopyWithImpl<$Res>
    implements $CorrespondentEvent_RepliedCopyWith<$Res> {
  _$CorrespondentEvent_RepliedCopyWithImpl(this._self, this._then);

  final CorrespondentEvent_Replied _self;
  final $Res Function(CorrespondentEvent_Replied) _then;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,}) {
  return _then(CorrespondentEvent_Replied(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CorrespondentEvent_Posted extends CorrespondentEvent {
  const CorrespondentEvent_Posted({required this.text, this.from}): super._();
  

 final  String text;
 final  String? from;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CorrespondentEvent_PostedCopyWith<CorrespondentEvent_Posted> get copyWith => _$CorrespondentEvent_PostedCopyWithImpl<CorrespondentEvent_Posted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CorrespondentEvent_Posted&&(identical(other.text, text) || other.text == text)&&(identical(other.from, from) || other.from == from));
}


@override
int get hashCode => Object.hash(runtimeType,text,from);

@override
String toString() {
  return 'CorrespondentEvent.posted(text: $text, from: $from)';
}


}

/// @nodoc
abstract mixin class $CorrespondentEvent_PostedCopyWith<$Res> implements $CorrespondentEventCopyWith<$Res> {
  factory $CorrespondentEvent_PostedCopyWith(CorrespondentEvent_Posted value, $Res Function(CorrespondentEvent_Posted) _then) = _$CorrespondentEvent_PostedCopyWithImpl;
@useResult
$Res call({
 String text, String? from
});




}
/// @nodoc
class _$CorrespondentEvent_PostedCopyWithImpl<$Res>
    implements $CorrespondentEvent_PostedCopyWith<$Res> {
  _$CorrespondentEvent_PostedCopyWithImpl(this._self, this._then);

  final CorrespondentEvent_Posted _self;
  final $Res Function(CorrespondentEvent_Posted) _then;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,Object? from = freezed,}) {
  return _then(CorrespondentEvent_Posted(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class CorrespondentEvent_TimedOut extends CorrespondentEvent {
  const CorrespondentEvent_TimedOut({required this.id, required this.reason}): super._();
  

 final  String id;
 final  String reason;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CorrespondentEvent_TimedOutCopyWith<CorrespondentEvent_TimedOut> get copyWith => _$CorrespondentEvent_TimedOutCopyWithImpl<CorrespondentEvent_TimedOut>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CorrespondentEvent_TimedOut&&(identical(other.id, id) || other.id == id)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,id,reason);

@override
String toString() {
  return 'CorrespondentEvent.timedOut(id: $id, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $CorrespondentEvent_TimedOutCopyWith<$Res> implements $CorrespondentEventCopyWith<$Res> {
  factory $CorrespondentEvent_TimedOutCopyWith(CorrespondentEvent_TimedOut value, $Res Function(CorrespondentEvent_TimedOut) _then) = _$CorrespondentEvent_TimedOutCopyWithImpl;
@useResult
$Res call({
 String id, String reason
});




}
/// @nodoc
class _$CorrespondentEvent_TimedOutCopyWithImpl<$Res>
    implements $CorrespondentEvent_TimedOutCopyWith<$Res> {
  _$CorrespondentEvent_TimedOutCopyWithImpl(this._self, this._then);

  final CorrespondentEvent_TimedOut _self;
  final $Res Function(CorrespondentEvent_TimedOut) _then;

/// Create a copy of CorrespondentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? reason = null,}) {
  return _then(CorrespondentEvent_TimedOut(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CorrespondentEvent_SessionsChanged extends CorrespondentEvent {
  const CorrespondentEvent_SessionsChanged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CorrespondentEvent_SessionsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CorrespondentEvent.sessionsChanged()';
}


}




// dart format on
