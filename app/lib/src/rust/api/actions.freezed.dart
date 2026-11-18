// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'actions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CommandRunEvent {

 String get runId;
/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEventCopyWith<CommandRunEvent> get copyWith => _$CommandRunEventCopyWithImpl<CommandRunEvent>(this as CommandRunEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent&&(identical(other.runId, runId) || other.runId == runId));
}


@override
int get hashCode => Object.hash(runtimeType,runId);

@override
String toString() {
  return 'CommandRunEvent(runId: $runId)';
}


}

/// @nodoc
abstract mixin class $CommandRunEventCopyWith<$Res>  {
  factory $CommandRunEventCopyWith(CommandRunEvent value, $Res Function(CommandRunEvent) _then) = _$CommandRunEventCopyWithImpl;
@useResult
$Res call({
 String runId
});




}
/// @nodoc
class _$CommandRunEventCopyWithImpl<$Res>
    implements $CommandRunEventCopyWith<$Res> {
  _$CommandRunEventCopyWithImpl(this._self, this._then);

  final CommandRunEvent _self;
  final $Res Function(CommandRunEvent) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runId = null,}) {
  return _then(_self.copyWith(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CommandRunEvent].
extension CommandRunEventPatterns on CommandRunEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CommandRunEvent_Started value)?  started,TResult Function( CommandRunEvent_Output value)?  output,TResult Function( CommandRunEvent_Detached value)?  detached,TResult Function( CommandRunEvent_Finished value)?  finished,TResult Function( CommandRunEvent_Cancelled value)?  cancelled,TResult Function( CommandRunEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CommandRunEvent_Started() when started != null:
return started(_that);case CommandRunEvent_Output() when output != null:
return output(_that);case CommandRunEvent_Detached() when detached != null:
return detached(_that);case CommandRunEvent_Finished() when finished != null:
return finished(_that);case CommandRunEvent_Cancelled() when cancelled != null:
return cancelled(_that);case CommandRunEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CommandRunEvent_Started value)  started,required TResult Function( CommandRunEvent_Output value)  output,required TResult Function( CommandRunEvent_Detached value)  detached,required TResult Function( CommandRunEvent_Finished value)  finished,required TResult Function( CommandRunEvent_Cancelled value)  cancelled,required TResult Function( CommandRunEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case CommandRunEvent_Started():
return started(_that);case CommandRunEvent_Output():
return output(_that);case CommandRunEvent_Detached():
return detached(_that);case CommandRunEvent_Finished():
return finished(_that);case CommandRunEvent_Cancelled():
return cancelled(_that);case CommandRunEvent_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CommandRunEvent_Started value)?  started,TResult? Function( CommandRunEvent_Output value)?  output,TResult? Function( CommandRunEvent_Detached value)?  detached,TResult? Function( CommandRunEvent_Finished value)?  finished,TResult? Function( CommandRunEvent_Cancelled value)?  cancelled,TResult? Function( CommandRunEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case CommandRunEvent_Started() when started != null:
return started(_that);case CommandRunEvent_Output() when output != null:
return output(_that);case CommandRunEvent_Detached() when detached != null:
return detached(_that);case CommandRunEvent_Finished() when finished != null:
return finished(_that);case CommandRunEvent_Cancelled() when cancelled != null:
return cancelled(_that);case CommandRunEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String runId,  String label,  String command,  bool cancellable)?  started,TResult Function( String runId,  CommandOutputStream stream,  List<String> lines)?  output,TResult Function( String runId,  int elapsedMs)?  detached,TResult Function( String runId,  int? exitCode,  int elapsedMs,  bool ok,  bool afterDetach,  int droppedLines,  String outputTail)?  finished,TResult Function( String runId,  int elapsedMs)?  cancelled,TResult Function( String runId,  String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CommandRunEvent_Started() when started != null:
return started(_that.runId,_that.label,_that.command,_that.cancellable);case CommandRunEvent_Output() when output != null:
return output(_that.runId,_that.stream,_that.lines);case CommandRunEvent_Detached() when detached != null:
return detached(_that.runId,_that.elapsedMs);case CommandRunEvent_Finished() when finished != null:
return finished(_that.runId,_that.exitCode,_that.elapsedMs,_that.ok,_that.afterDetach,_that.droppedLines,_that.outputTail);case CommandRunEvent_Cancelled() when cancelled != null:
return cancelled(_that.runId,_that.elapsedMs);case CommandRunEvent_Failed() when failed != null:
return failed(_that.runId,_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String runId,  String label,  String command,  bool cancellable)  started,required TResult Function( String runId,  CommandOutputStream stream,  List<String> lines)  output,required TResult Function( String runId,  int elapsedMs)  detached,required TResult Function( String runId,  int? exitCode,  int elapsedMs,  bool ok,  bool afterDetach,  int droppedLines,  String outputTail)  finished,required TResult Function( String runId,  int elapsedMs)  cancelled,required TResult Function( String runId,  String detail)  failed,}) {final _that = this;
switch (_that) {
case CommandRunEvent_Started():
return started(_that.runId,_that.label,_that.command,_that.cancellable);case CommandRunEvent_Output():
return output(_that.runId,_that.stream,_that.lines);case CommandRunEvent_Detached():
return detached(_that.runId,_that.elapsedMs);case CommandRunEvent_Finished():
return finished(_that.runId,_that.exitCode,_that.elapsedMs,_that.ok,_that.afterDetach,_that.droppedLines,_that.outputTail);case CommandRunEvent_Cancelled():
return cancelled(_that.runId,_that.elapsedMs);case CommandRunEvent_Failed():
return failed(_that.runId,_that.detail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String runId,  String label,  String command,  bool cancellable)?  started,TResult? Function( String runId,  CommandOutputStream stream,  List<String> lines)?  output,TResult? Function( String runId,  int elapsedMs)?  detached,TResult? Function( String runId,  int? exitCode,  int elapsedMs,  bool ok,  bool afterDetach,  int droppedLines,  String outputTail)?  finished,TResult? Function( String runId,  int elapsedMs)?  cancelled,TResult? Function( String runId,  String detail)?  failed,}) {final _that = this;
switch (_that) {
case CommandRunEvent_Started() when started != null:
return started(_that.runId,_that.label,_that.command,_that.cancellable);case CommandRunEvent_Output() when output != null:
return output(_that.runId,_that.stream,_that.lines);case CommandRunEvent_Detached() when detached != null:
return detached(_that.runId,_that.elapsedMs);case CommandRunEvent_Finished() when finished != null:
return finished(_that.runId,_that.exitCode,_that.elapsedMs,_that.ok,_that.afterDetach,_that.droppedLines,_that.outputTail);case CommandRunEvent_Cancelled() when cancelled != null:
return cancelled(_that.runId,_that.elapsedMs);case CommandRunEvent_Failed() when failed != null:
return failed(_that.runId,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class CommandRunEvent_Started extends CommandRunEvent {
  const CommandRunEvent_Started({required this.runId, required this.label, required this.command, required this.cancellable}): super._();
  

@override final  String runId;
 final  String label;
 final  String command;
/// `false` en la ruta elevada: un proceso de integridad media no
/// puede matar a uno de integridad alta, asi que la UI tiene que
/// esconder el boton de cancelar en vez de ofrecer uno inerte.
 final  bool cancellable;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEvent_StartedCopyWith<CommandRunEvent_Started> get copyWith => _$CommandRunEvent_StartedCopyWithImpl<CommandRunEvent_Started>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent_Started&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.label, label) || other.label == label)&&(identical(other.command, command) || other.command == command)&&(identical(other.cancellable, cancellable) || other.cancellable == cancellable));
}


@override
int get hashCode => Object.hash(runtimeType,runId,label,command,cancellable);

@override
String toString() {
  return 'CommandRunEvent.started(runId: $runId, label: $label, command: $command, cancellable: $cancellable)';
}


}

/// @nodoc
abstract mixin class $CommandRunEvent_StartedCopyWith<$Res> implements $CommandRunEventCopyWith<$Res> {
  factory $CommandRunEvent_StartedCopyWith(CommandRunEvent_Started value, $Res Function(CommandRunEvent_Started) _then) = _$CommandRunEvent_StartedCopyWithImpl;
@override @useResult
$Res call({
 String runId, String label, String command, bool cancellable
});




}
/// @nodoc
class _$CommandRunEvent_StartedCopyWithImpl<$Res>
    implements $CommandRunEvent_StartedCopyWith<$Res> {
  _$CommandRunEvent_StartedCopyWithImpl(this._self, this._then);

  final CommandRunEvent_Started _self;
  final $Res Function(CommandRunEvent_Started) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? label = null,Object? command = null,Object? cancellable = null,}) {
  return _then(CommandRunEvent_Started(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,cancellable: null == cancellable ? _self.cancellable : cancellable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class CommandRunEvent_Output extends CommandRunEvent {
  const CommandRunEvent_Output({required this.runId, required this.stream, required final  List<String> lines}): _lines = lines,super._();
  

@override final  String runId;
 final  CommandOutputStream stream;
 final  List<String> _lines;
 List<String> get lines {
  if (_lines is EqualUnmodifiableListView) return _lines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lines);
}


/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEvent_OutputCopyWith<CommandRunEvent_Output> get copyWith => _$CommandRunEvent_OutputCopyWithImpl<CommandRunEvent_Output>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent_Output&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.stream, stream) || other.stream == stream)&&const DeepCollectionEquality().equals(other._lines, _lines));
}


@override
int get hashCode => Object.hash(runtimeType,runId,stream,const DeepCollectionEquality().hash(_lines));

@override
String toString() {
  return 'CommandRunEvent.output(runId: $runId, stream: $stream, lines: $lines)';
}


}

/// @nodoc
abstract mixin class $CommandRunEvent_OutputCopyWith<$Res> implements $CommandRunEventCopyWith<$Res> {
  factory $CommandRunEvent_OutputCopyWith(CommandRunEvent_Output value, $Res Function(CommandRunEvent_Output) _then) = _$CommandRunEvent_OutputCopyWithImpl;
@override @useResult
$Res call({
 String runId, CommandOutputStream stream, List<String> lines
});




}
/// @nodoc
class _$CommandRunEvent_OutputCopyWithImpl<$Res>
    implements $CommandRunEvent_OutputCopyWith<$Res> {
  _$CommandRunEvent_OutputCopyWithImpl(this._self, this._then);

  final CommandRunEvent_Output _self;
  final $Res Function(CommandRunEvent_Output) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? stream = null,Object? lines = null,}) {
  return _then(CommandRunEvent_Output(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,stream: null == stream ? _self.stream : stream // ignore: cast_nullable_to_non_nullable
as CommandOutputStream,lines: null == lines ? _self._lines : lines // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class CommandRunEvent_Detached extends CommandRunEvent {
  const CommandRunEvent_Detached({required this.runId, required this.elapsedMs}): super._();
  

@override final  String runId;
 final  int elapsedMs;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEvent_DetachedCopyWith<CommandRunEvent_Detached> get copyWith => _$CommandRunEvent_DetachedCopyWithImpl<CommandRunEvent_Detached>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent_Detached&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.elapsedMs, elapsedMs) || other.elapsedMs == elapsedMs));
}


@override
int get hashCode => Object.hash(runtimeType,runId,elapsedMs);

@override
String toString() {
  return 'CommandRunEvent.detached(runId: $runId, elapsedMs: $elapsedMs)';
}


}

/// @nodoc
abstract mixin class $CommandRunEvent_DetachedCopyWith<$Res> implements $CommandRunEventCopyWith<$Res> {
  factory $CommandRunEvent_DetachedCopyWith(CommandRunEvent_Detached value, $Res Function(CommandRunEvent_Detached) _then) = _$CommandRunEvent_DetachedCopyWithImpl;
@override @useResult
$Res call({
 String runId, int elapsedMs
});




}
/// @nodoc
class _$CommandRunEvent_DetachedCopyWithImpl<$Res>
    implements $CommandRunEvent_DetachedCopyWith<$Res> {
  _$CommandRunEvent_DetachedCopyWithImpl(this._self, this._then);

  final CommandRunEvent_Detached _self;
  final $Res Function(CommandRunEvent_Detached) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? elapsedMs = null,}) {
  return _then(CommandRunEvent_Detached(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CommandRunEvent_Finished extends CommandRunEvent {
  const CommandRunEvent_Finished({required this.runId, this.exitCode, required this.elapsedMs, required this.ok, required this.afterDetach, required this.droppedLines, required this.outputTail}): super._();
  

@override final  String runId;
 final  int? exitCode;
 final  int elapsedMs;
 final  bool ok;
/// Ya se habia dado por "lanzada": no hay ninguna notificacion viva
/// para este run, asi que si `ok` es `false` hay que abrir una nueva.
 final  bool afterDetach;
 final  int droppedLines;
 final  String outputTail;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEvent_FinishedCopyWith<CommandRunEvent_Finished> get copyWith => _$CommandRunEvent_FinishedCopyWithImpl<CommandRunEvent_Finished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent_Finished&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.elapsedMs, elapsedMs) || other.elapsedMs == elapsedMs)&&(identical(other.ok, ok) || other.ok == ok)&&(identical(other.afterDetach, afterDetach) || other.afterDetach == afterDetach)&&(identical(other.droppedLines, droppedLines) || other.droppedLines == droppedLines)&&(identical(other.outputTail, outputTail) || other.outputTail == outputTail));
}


@override
int get hashCode => Object.hash(runtimeType,runId,exitCode,elapsedMs,ok,afterDetach,droppedLines,outputTail);

@override
String toString() {
  return 'CommandRunEvent.finished(runId: $runId, exitCode: $exitCode, elapsedMs: $elapsedMs, ok: $ok, afterDetach: $afterDetach, droppedLines: $droppedLines, outputTail: $outputTail)';
}


}

/// @nodoc
abstract mixin class $CommandRunEvent_FinishedCopyWith<$Res> implements $CommandRunEventCopyWith<$Res> {
  factory $CommandRunEvent_FinishedCopyWith(CommandRunEvent_Finished value, $Res Function(CommandRunEvent_Finished) _then) = _$CommandRunEvent_FinishedCopyWithImpl;
@override @useResult
$Res call({
 String runId, int? exitCode, int elapsedMs, bool ok, bool afterDetach, int droppedLines, String outputTail
});




}
/// @nodoc
class _$CommandRunEvent_FinishedCopyWithImpl<$Res>
    implements $CommandRunEvent_FinishedCopyWith<$Res> {
  _$CommandRunEvent_FinishedCopyWithImpl(this._self, this._then);

  final CommandRunEvent_Finished _self;
  final $Res Function(CommandRunEvent_Finished) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? exitCode = freezed,Object? elapsedMs = null,Object? ok = null,Object? afterDetach = null,Object? droppedLines = null,Object? outputTail = null,}) {
  return _then(CommandRunEvent_Finished(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as int,ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,afterDetach: null == afterDetach ? _self.afterDetach : afterDetach // ignore: cast_nullable_to_non_nullable
as bool,droppedLines: null == droppedLines ? _self.droppedLines : droppedLines // ignore: cast_nullable_to_non_nullable
as int,outputTail: null == outputTail ? _self.outputTail : outputTail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CommandRunEvent_Cancelled extends CommandRunEvent {
  const CommandRunEvent_Cancelled({required this.runId, required this.elapsedMs}): super._();
  

@override final  String runId;
 final  int elapsedMs;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEvent_CancelledCopyWith<CommandRunEvent_Cancelled> get copyWith => _$CommandRunEvent_CancelledCopyWithImpl<CommandRunEvent_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent_Cancelled&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.elapsedMs, elapsedMs) || other.elapsedMs == elapsedMs));
}


@override
int get hashCode => Object.hash(runtimeType,runId,elapsedMs);

@override
String toString() {
  return 'CommandRunEvent.cancelled(runId: $runId, elapsedMs: $elapsedMs)';
}


}

/// @nodoc
abstract mixin class $CommandRunEvent_CancelledCopyWith<$Res> implements $CommandRunEventCopyWith<$Res> {
  factory $CommandRunEvent_CancelledCopyWith(CommandRunEvent_Cancelled value, $Res Function(CommandRunEvent_Cancelled) _then) = _$CommandRunEvent_CancelledCopyWithImpl;
@override @useResult
$Res call({
 String runId, int elapsedMs
});




}
/// @nodoc
class _$CommandRunEvent_CancelledCopyWithImpl<$Res>
    implements $CommandRunEvent_CancelledCopyWith<$Res> {
  _$CommandRunEvent_CancelledCopyWithImpl(this._self, this._then);

  final CommandRunEvent_Cancelled _self;
  final $Res Function(CommandRunEvent_Cancelled) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? elapsedMs = null,}) {
  return _then(CommandRunEvent_Cancelled(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CommandRunEvent_Failed extends CommandRunEvent {
  const CommandRunEvent_Failed({required this.runId, required this.detail}): super._();
  

@override final  String runId;
 final  String detail;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandRunEvent_FailedCopyWith<CommandRunEvent_Failed> get copyWith => _$CommandRunEvent_FailedCopyWithImpl<CommandRunEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandRunEvent_Failed&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,runId,detail);

@override
String toString() {
  return 'CommandRunEvent.failed(runId: $runId, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $CommandRunEvent_FailedCopyWith<$Res> implements $CommandRunEventCopyWith<$Res> {
  factory $CommandRunEvent_FailedCopyWith(CommandRunEvent_Failed value, $Res Function(CommandRunEvent_Failed) _then) = _$CommandRunEvent_FailedCopyWithImpl;
@override @useResult
$Res call({
 String runId, String detail
});




}
/// @nodoc
class _$CommandRunEvent_FailedCopyWithImpl<$Res>
    implements $CommandRunEvent_FailedCopyWith<$Res> {
  _$CommandRunEvent_FailedCopyWithImpl(this._self, this._then);

  final CommandRunEvent_Failed _self;
  final $Res Function(CommandRunEvent_Failed) _then;

/// Create a copy of CommandRunEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runId = null,Object? detail = null,}) {
  return _then(CommandRunEvent_Failed(
runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
