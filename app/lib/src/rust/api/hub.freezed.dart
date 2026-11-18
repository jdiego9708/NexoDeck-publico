// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hub.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HubSubscriptionEvent {

 String get subscriptionId;
/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionEventCopyWith<HubSubscriptionEvent> get copyWith => _$HubSubscriptionEventCopyWithImpl<HubSubscriptionEvent>(this as HubSubscriptionEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionEvent&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId));
}


@override
int get hashCode => Object.hash(runtimeType,subscriptionId);

@override
String toString() {
  return 'HubSubscriptionEvent(subscriptionId: $subscriptionId)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionEventCopyWith<$Res>  {
  factory $HubSubscriptionEventCopyWith(HubSubscriptionEvent value, $Res Function(HubSubscriptionEvent) _then) = _$HubSubscriptionEventCopyWithImpl;
@useResult
$Res call({
 String subscriptionId
});




}
/// @nodoc
class _$HubSubscriptionEventCopyWithImpl<$Res>
    implements $HubSubscriptionEventCopyWith<$Res> {
  _$HubSubscriptionEventCopyWithImpl(this._self, this._then);

  final HubSubscriptionEvent _self;
  final $Res Function(HubSubscriptionEvent) _then;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? subscriptionId = null,}) {
  return _then(_self.copyWith(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [HubSubscriptionEvent].
extension HubSubscriptionEventPatterns on HubSubscriptionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( HubSubscriptionEvent_Connected value)?  connected,TResult Function( HubSubscriptionEvent_MessageReceived value)?  messageReceived,TResult Function( HubSubscriptionEvent_Disconnected value)?  disconnected,TResult Function( HubSubscriptionEvent_Stopped value)?  stopped,TResult Function( HubSubscriptionEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case HubSubscriptionEvent_Connected() when connected != null:
return connected(_that);case HubSubscriptionEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that);case HubSubscriptionEvent_Disconnected() when disconnected != null:
return disconnected(_that);case HubSubscriptionEvent_Stopped() when stopped != null:
return stopped(_that);case HubSubscriptionEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( HubSubscriptionEvent_Connected value)  connected,required TResult Function( HubSubscriptionEvent_MessageReceived value)  messageReceived,required TResult Function( HubSubscriptionEvent_Disconnected value)  disconnected,required TResult Function( HubSubscriptionEvent_Stopped value)  stopped,required TResult Function( HubSubscriptionEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case HubSubscriptionEvent_Connected():
return connected(_that);case HubSubscriptionEvent_MessageReceived():
return messageReceived(_that);case HubSubscriptionEvent_Disconnected():
return disconnected(_that);case HubSubscriptionEvent_Stopped():
return stopped(_that);case HubSubscriptionEvent_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( HubSubscriptionEvent_Connected value)?  connected,TResult? Function( HubSubscriptionEvent_MessageReceived value)?  messageReceived,TResult? Function( HubSubscriptionEvent_Disconnected value)?  disconnected,TResult? Function( HubSubscriptionEvent_Stopped value)?  stopped,TResult? Function( HubSubscriptionEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case HubSubscriptionEvent_Connected() when connected != null:
return connected(_that);case HubSubscriptionEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that);case HubSubscriptionEvent_Disconnected() when disconnected != null:
return disconnected(_that);case HubSubscriptionEvent_Stopped() when stopped != null:
return stopped(_that);case HubSubscriptionEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String subscriptionId)?  connected,TResult Function( String subscriptionId,  String eventName,  String payloadJson)?  messageReceived,TResult Function( String subscriptionId,  String reason)?  disconnected,TResult Function( String subscriptionId)?  stopped,TResult Function( String subscriptionId,  String error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case HubSubscriptionEvent_Connected() when connected != null:
return connected(_that.subscriptionId);case HubSubscriptionEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that.subscriptionId,_that.eventName,_that.payloadJson);case HubSubscriptionEvent_Disconnected() when disconnected != null:
return disconnected(_that.subscriptionId,_that.reason);case HubSubscriptionEvent_Stopped() when stopped != null:
return stopped(_that.subscriptionId);case HubSubscriptionEvent_Failed() when failed != null:
return failed(_that.subscriptionId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String subscriptionId)  connected,required TResult Function( String subscriptionId,  String eventName,  String payloadJson)  messageReceived,required TResult Function( String subscriptionId,  String reason)  disconnected,required TResult Function( String subscriptionId)  stopped,required TResult Function( String subscriptionId,  String error)  failed,}) {final _that = this;
switch (_that) {
case HubSubscriptionEvent_Connected():
return connected(_that.subscriptionId);case HubSubscriptionEvent_MessageReceived():
return messageReceived(_that.subscriptionId,_that.eventName,_that.payloadJson);case HubSubscriptionEvent_Disconnected():
return disconnected(_that.subscriptionId,_that.reason);case HubSubscriptionEvent_Stopped():
return stopped(_that.subscriptionId);case HubSubscriptionEvent_Failed():
return failed(_that.subscriptionId,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String subscriptionId)?  connected,TResult? Function( String subscriptionId,  String eventName,  String payloadJson)?  messageReceived,TResult? Function( String subscriptionId,  String reason)?  disconnected,TResult? Function( String subscriptionId)?  stopped,TResult? Function( String subscriptionId,  String error)?  failed,}) {final _that = this;
switch (_that) {
case HubSubscriptionEvent_Connected() when connected != null:
return connected(_that.subscriptionId);case HubSubscriptionEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that.subscriptionId,_that.eventName,_that.payloadJson);case HubSubscriptionEvent_Disconnected() when disconnected != null:
return disconnected(_that.subscriptionId,_that.reason);case HubSubscriptionEvent_Stopped() when stopped != null:
return stopped(_that.subscriptionId);case HubSubscriptionEvent_Failed() when failed != null:
return failed(_that.subscriptionId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class HubSubscriptionEvent_Connected extends HubSubscriptionEvent {
  const HubSubscriptionEvent_Connected({required this.subscriptionId}): super._();
  

@override final  String subscriptionId;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionEvent_ConnectedCopyWith<HubSubscriptionEvent_Connected> get copyWith => _$HubSubscriptionEvent_ConnectedCopyWithImpl<HubSubscriptionEvent_Connected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionEvent_Connected&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId));
}


@override
int get hashCode => Object.hash(runtimeType,subscriptionId);

@override
String toString() {
  return 'HubSubscriptionEvent.connected(subscriptionId: $subscriptionId)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionEvent_ConnectedCopyWith<$Res> implements $HubSubscriptionEventCopyWith<$Res> {
  factory $HubSubscriptionEvent_ConnectedCopyWith(HubSubscriptionEvent_Connected value, $Res Function(HubSubscriptionEvent_Connected) _then) = _$HubSubscriptionEvent_ConnectedCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId
});




}
/// @nodoc
class _$HubSubscriptionEvent_ConnectedCopyWithImpl<$Res>
    implements $HubSubscriptionEvent_ConnectedCopyWith<$Res> {
  _$HubSubscriptionEvent_ConnectedCopyWithImpl(this._self, this._then);

  final HubSubscriptionEvent_Connected _self;
  final $Res Function(HubSubscriptionEvent_Connected) _then;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,}) {
  return _then(HubSubscriptionEvent_Connected(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class HubSubscriptionEvent_MessageReceived extends HubSubscriptionEvent {
  const HubSubscriptionEvent_MessageReceived({required this.subscriptionId, required this.eventName, required this.payloadJson}): super._();
  

@override final  String subscriptionId;
 final  String eventName;
 final  String payloadJson;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionEvent_MessageReceivedCopyWith<HubSubscriptionEvent_MessageReceived> get copyWith => _$HubSubscriptionEvent_MessageReceivedCopyWithImpl<HubSubscriptionEvent_MessageReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionEvent_MessageReceived&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId)&&(identical(other.eventName, eventName) || other.eventName == eventName)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson));
}


@override
int get hashCode => Object.hash(runtimeType,subscriptionId,eventName,payloadJson);

@override
String toString() {
  return 'HubSubscriptionEvent.messageReceived(subscriptionId: $subscriptionId, eventName: $eventName, payloadJson: $payloadJson)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionEvent_MessageReceivedCopyWith<$Res> implements $HubSubscriptionEventCopyWith<$Res> {
  factory $HubSubscriptionEvent_MessageReceivedCopyWith(HubSubscriptionEvent_MessageReceived value, $Res Function(HubSubscriptionEvent_MessageReceived) _then) = _$HubSubscriptionEvent_MessageReceivedCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId, String eventName, String payloadJson
});




}
/// @nodoc
class _$HubSubscriptionEvent_MessageReceivedCopyWithImpl<$Res>
    implements $HubSubscriptionEvent_MessageReceivedCopyWith<$Res> {
  _$HubSubscriptionEvent_MessageReceivedCopyWithImpl(this._self, this._then);

  final HubSubscriptionEvent_MessageReceived _self;
  final $Res Function(HubSubscriptionEvent_MessageReceived) _then;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,Object? eventName = null,Object? payloadJson = null,}) {
  return _then(HubSubscriptionEvent_MessageReceived(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,eventName: null == eventName ? _self.eventName : eventName // ignore: cast_nullable_to_non_nullable
as String,payloadJson: null == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class HubSubscriptionEvent_Disconnected extends HubSubscriptionEvent {
  const HubSubscriptionEvent_Disconnected({required this.subscriptionId, required this.reason}): super._();
  

@override final  String subscriptionId;
 final  String reason;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionEvent_DisconnectedCopyWith<HubSubscriptionEvent_Disconnected> get copyWith => _$HubSubscriptionEvent_DisconnectedCopyWithImpl<HubSubscriptionEvent_Disconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionEvent_Disconnected&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,subscriptionId,reason);

@override
String toString() {
  return 'HubSubscriptionEvent.disconnected(subscriptionId: $subscriptionId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionEvent_DisconnectedCopyWith<$Res> implements $HubSubscriptionEventCopyWith<$Res> {
  factory $HubSubscriptionEvent_DisconnectedCopyWith(HubSubscriptionEvent_Disconnected value, $Res Function(HubSubscriptionEvent_Disconnected) _then) = _$HubSubscriptionEvent_DisconnectedCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId, String reason
});




}
/// @nodoc
class _$HubSubscriptionEvent_DisconnectedCopyWithImpl<$Res>
    implements $HubSubscriptionEvent_DisconnectedCopyWith<$Res> {
  _$HubSubscriptionEvent_DisconnectedCopyWithImpl(this._self, this._then);

  final HubSubscriptionEvent_Disconnected _self;
  final $Res Function(HubSubscriptionEvent_Disconnected) _then;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,Object? reason = null,}) {
  return _then(HubSubscriptionEvent_Disconnected(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class HubSubscriptionEvent_Stopped extends HubSubscriptionEvent {
  const HubSubscriptionEvent_Stopped({required this.subscriptionId}): super._();
  

@override final  String subscriptionId;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionEvent_StoppedCopyWith<HubSubscriptionEvent_Stopped> get copyWith => _$HubSubscriptionEvent_StoppedCopyWithImpl<HubSubscriptionEvent_Stopped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionEvent_Stopped&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId));
}


@override
int get hashCode => Object.hash(runtimeType,subscriptionId);

@override
String toString() {
  return 'HubSubscriptionEvent.stopped(subscriptionId: $subscriptionId)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionEvent_StoppedCopyWith<$Res> implements $HubSubscriptionEventCopyWith<$Res> {
  factory $HubSubscriptionEvent_StoppedCopyWith(HubSubscriptionEvent_Stopped value, $Res Function(HubSubscriptionEvent_Stopped) _then) = _$HubSubscriptionEvent_StoppedCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId
});




}
/// @nodoc
class _$HubSubscriptionEvent_StoppedCopyWithImpl<$Res>
    implements $HubSubscriptionEvent_StoppedCopyWith<$Res> {
  _$HubSubscriptionEvent_StoppedCopyWithImpl(this._self, this._then);

  final HubSubscriptionEvent_Stopped _self;
  final $Res Function(HubSubscriptionEvent_Stopped) _then;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,}) {
  return _then(HubSubscriptionEvent_Stopped(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class HubSubscriptionEvent_Failed extends HubSubscriptionEvent {
  const HubSubscriptionEvent_Failed({required this.subscriptionId, required this.error}): super._();
  

@override final  String subscriptionId;
 final  String error;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionEvent_FailedCopyWith<HubSubscriptionEvent_Failed> get copyWith => _$HubSubscriptionEvent_FailedCopyWithImpl<HubSubscriptionEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionEvent_Failed&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,subscriptionId,error);

@override
String toString() {
  return 'HubSubscriptionEvent.failed(subscriptionId: $subscriptionId, error: $error)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionEvent_FailedCopyWith<$Res> implements $HubSubscriptionEventCopyWith<$Res> {
  factory $HubSubscriptionEvent_FailedCopyWith(HubSubscriptionEvent_Failed value, $Res Function(HubSubscriptionEvent_Failed) _then) = _$HubSubscriptionEvent_FailedCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId, String error
});




}
/// @nodoc
class _$HubSubscriptionEvent_FailedCopyWithImpl<$Res>
    implements $HubSubscriptionEvent_FailedCopyWith<$Res> {
  _$HubSubscriptionEvent_FailedCopyWithImpl(this._self, this._then);

  final HubSubscriptionEvent_Failed _self;
  final $Res Function(HubSubscriptionEvent_Failed) _then;

/// Create a copy of HubSubscriptionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,Object? error = null,}) {
  return _then(HubSubscriptionEvent_Failed(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$HubSubscriptionKind {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'HubSubscriptionKind()';
}


}

/// @nodoc
class $HubSubscriptionKindCopyWith<$Res>  {
$HubSubscriptionKindCopyWith(HubSubscriptionKind _, $Res Function(HubSubscriptionKind) __);
}


/// Adds pattern-matching-related methods to [HubSubscriptionKind].
extension HubSubscriptionKindPatterns on HubSubscriptionKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( HubSubscriptionKind_SignalR value)?  signalR,TResult Function( HubSubscriptionKind_RawWebSocket value)?  rawWebSocket,required TResult orElse(),}){
final _that = this;
switch (_that) {
case HubSubscriptionKind_SignalR() when signalR != null:
return signalR(_that);case HubSubscriptionKind_RawWebSocket() when rawWebSocket != null:
return rawWebSocket(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( HubSubscriptionKind_SignalR value)  signalR,required TResult Function( HubSubscriptionKind_RawWebSocket value)  rawWebSocket,}){
final _that = this;
switch (_that) {
case HubSubscriptionKind_SignalR():
return signalR(_that);case HubSubscriptionKind_RawWebSocket():
return rawWebSocket(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( HubSubscriptionKind_SignalR value)?  signalR,TResult? Function( HubSubscriptionKind_RawWebSocket value)?  rawWebSocket,}){
final _that = this;
switch (_that) {
case HubSubscriptionKind_SignalR() when signalR != null:
return signalR(_that);case HubSubscriptionKind_RawWebSocket() when rawWebSocket != null:
return rawWebSocket(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String hubPath,  String invokeMethod,  List<String> invokeArgsJson)?  signalR,TResult Function()?  rawWebSocket,required TResult orElse(),}) {final _that = this;
switch (_that) {
case HubSubscriptionKind_SignalR() when signalR != null:
return signalR(_that.hubPath,_that.invokeMethod,_that.invokeArgsJson);case HubSubscriptionKind_RawWebSocket() when rawWebSocket != null:
return rawWebSocket();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String hubPath,  String invokeMethod,  List<String> invokeArgsJson)  signalR,required TResult Function()  rawWebSocket,}) {final _that = this;
switch (_that) {
case HubSubscriptionKind_SignalR():
return signalR(_that.hubPath,_that.invokeMethod,_that.invokeArgsJson);case HubSubscriptionKind_RawWebSocket():
return rawWebSocket();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String hubPath,  String invokeMethod,  List<String> invokeArgsJson)?  signalR,TResult? Function()?  rawWebSocket,}) {final _that = this;
switch (_that) {
case HubSubscriptionKind_SignalR() when signalR != null:
return signalR(_that.hubPath,_that.invokeMethod,_that.invokeArgsJson);case HubSubscriptionKind_RawWebSocket() when rawWebSocket != null:
return rawWebSocket();case _:
  return null;

}
}

}

/// @nodoc


class HubSubscriptionKind_SignalR extends HubSubscriptionKind {
  const HubSubscriptionKind_SignalR({required this.hubPath, required this.invokeMethod, required final  List<String> invokeArgsJson}): _invokeArgsJson = invokeArgsJson,super._();
  

/// Ej. `/hubs/plant-training-progress`.
 final  String hubPath;
/// Metodo del hub a invocar apenas conecta, ej. `SubscribeToJob`.
 final  String invokeMethod;
/// Cada argumento ya serializado a JSON (`"job-123"`, `42`, `true`) --
/// el lado Dart arma la lista, este archivo solo la reparsea para
/// mandarla como `serde_json::Value` real y no como texto plano.
 final  List<String> _invokeArgsJson;
/// Cada argumento ya serializado a JSON (`"job-123"`, `42`, `true`) --
/// el lado Dart arma la lista, este archivo solo la reparsea para
/// mandarla como `serde_json::Value` real y no como texto plano.
 List<String> get invokeArgsJson {
  if (_invokeArgsJson is EqualUnmodifiableListView) return _invokeArgsJson;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_invokeArgsJson);
}


/// Create a copy of HubSubscriptionKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HubSubscriptionKind_SignalRCopyWith<HubSubscriptionKind_SignalR> get copyWith => _$HubSubscriptionKind_SignalRCopyWithImpl<HubSubscriptionKind_SignalR>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionKind_SignalR&&(identical(other.hubPath, hubPath) || other.hubPath == hubPath)&&(identical(other.invokeMethod, invokeMethod) || other.invokeMethod == invokeMethod)&&const DeepCollectionEquality().equals(other._invokeArgsJson, _invokeArgsJson));
}


@override
int get hashCode => Object.hash(runtimeType,hubPath,invokeMethod,const DeepCollectionEquality().hash(_invokeArgsJson));

@override
String toString() {
  return 'HubSubscriptionKind.signalR(hubPath: $hubPath, invokeMethod: $invokeMethod, invokeArgsJson: $invokeArgsJson)';
}


}

/// @nodoc
abstract mixin class $HubSubscriptionKind_SignalRCopyWith<$Res> implements $HubSubscriptionKindCopyWith<$Res> {
  factory $HubSubscriptionKind_SignalRCopyWith(HubSubscriptionKind_SignalR value, $Res Function(HubSubscriptionKind_SignalR) _then) = _$HubSubscriptionKind_SignalRCopyWithImpl;
@useResult
$Res call({
 String hubPath, String invokeMethod, List<String> invokeArgsJson
});




}
/// @nodoc
class _$HubSubscriptionKind_SignalRCopyWithImpl<$Res>
    implements $HubSubscriptionKind_SignalRCopyWith<$Res> {
  _$HubSubscriptionKind_SignalRCopyWithImpl(this._self, this._then);

  final HubSubscriptionKind_SignalR _self;
  final $Res Function(HubSubscriptionKind_SignalR) _then;

/// Create a copy of HubSubscriptionKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hubPath = null,Object? invokeMethod = null,Object? invokeArgsJson = null,}) {
  return _then(HubSubscriptionKind_SignalR(
hubPath: null == hubPath ? _self.hubPath : hubPath // ignore: cast_nullable_to_non_nullable
as String,invokeMethod: null == invokeMethod ? _self.invokeMethod : invokeMethod // ignore: cast_nullable_to_non_nullable
as String,invokeArgsJson: null == invokeArgsJson ? _self._invokeArgsJson : invokeArgsJson // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class HubSubscriptionKind_RawWebSocket extends HubSubscriptionKind {
  const HubSubscriptionKind_RawWebSocket(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HubSubscriptionKind_RawWebSocket);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'HubSubscriptionKind.rawWebSocket()';
}


}




// dart format on
