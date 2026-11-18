// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pairing.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PairingEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PairingEvent()';
}


}

/// @nodoc
class $PairingEventCopyWith<$Res>  {
$PairingEventCopyWith(PairingEvent _, $Res Function(PairingEvent) __);
}


/// Adds pattern-matching-related methods to [PairingEvent].
extension PairingEventPatterns on PairingEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PairingEvent_DeviceRequestedPairing value)?  deviceRequestedPairing,TResult Function( PairingEvent_HostPinReceived value)?  hostPinReceived,TResult Function( PairingEvent_PairingSucceeded value)?  pairingSucceeded,TResult Function( PairingEvent_PairingRejected value)?  pairingRejected,TResult Function( PairingEvent_PairingRequestedWhileDisarmed value)?  pairingRequestedWhileDisarmed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PairingEvent_DeviceRequestedPairing() when deviceRequestedPairing != null:
return deviceRequestedPairing(_that);case PairingEvent_HostPinReceived() when hostPinReceived != null:
return hostPinReceived(_that);case PairingEvent_PairingSucceeded() when pairingSucceeded != null:
return pairingSucceeded(_that);case PairingEvent_PairingRejected() when pairingRejected != null:
return pairingRejected(_that);case PairingEvent_PairingRequestedWhileDisarmed() when pairingRequestedWhileDisarmed != null:
return pairingRequestedWhileDisarmed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PairingEvent_DeviceRequestedPairing value)  deviceRequestedPairing,required TResult Function( PairingEvent_HostPinReceived value)  hostPinReceived,required TResult Function( PairingEvent_PairingSucceeded value)  pairingSucceeded,required TResult Function( PairingEvent_PairingRejected value)  pairingRejected,required TResult Function( PairingEvent_PairingRequestedWhileDisarmed value)  pairingRequestedWhileDisarmed,}){
final _that = this;
switch (_that) {
case PairingEvent_DeviceRequestedPairing():
return deviceRequestedPairing(_that);case PairingEvent_HostPinReceived():
return hostPinReceived(_that);case PairingEvent_PairingSucceeded():
return pairingSucceeded(_that);case PairingEvent_PairingRejected():
return pairingRejected(_that);case PairingEvent_PairingRequestedWhileDisarmed():
return pairingRequestedWhileDisarmed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PairingEvent_DeviceRequestedPairing value)?  deviceRequestedPairing,TResult? Function( PairingEvent_HostPinReceived value)?  hostPinReceived,TResult? Function( PairingEvent_PairingSucceeded value)?  pairingSucceeded,TResult? Function( PairingEvent_PairingRejected value)?  pairingRejected,TResult? Function( PairingEvent_PairingRequestedWhileDisarmed value)?  pairingRequestedWhileDisarmed,}){
final _that = this;
switch (_that) {
case PairingEvent_DeviceRequestedPairing() when deviceRequestedPairing != null:
return deviceRequestedPairing(_that);case PairingEvent_HostPinReceived() when hostPinReceived != null:
return hostPinReceived(_that);case PairingEvent_PairingSucceeded() when pairingSucceeded != null:
return pairingSucceeded(_that);case PairingEvent_PairingRejected() when pairingRejected != null:
return pairingRejected(_that);case PairingEvent_PairingRequestedWhileDisarmed() when pairingRequestedWhileDisarmed != null:
return pairingRequestedWhileDisarmed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String deviceName,  DevicePlatform platform)?  deviceRequestedPairing,TResult Function( String pin,  String hostName,  DevicePlatform hostPlatform)?  hostPinReceived,TResult Function( String deviceId,  String certFingerprint)?  pairingSucceeded,TResult Function( String reason)?  pairingRejected,TResult Function( String deviceName,  DevicePlatform platform)?  pairingRequestedWhileDisarmed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PairingEvent_DeviceRequestedPairing() when deviceRequestedPairing != null:
return deviceRequestedPairing(_that.deviceName,_that.platform);case PairingEvent_HostPinReceived() when hostPinReceived != null:
return hostPinReceived(_that.pin,_that.hostName,_that.hostPlatform);case PairingEvent_PairingSucceeded() when pairingSucceeded != null:
return pairingSucceeded(_that.deviceId,_that.certFingerprint);case PairingEvent_PairingRejected() when pairingRejected != null:
return pairingRejected(_that.reason);case PairingEvent_PairingRequestedWhileDisarmed() when pairingRequestedWhileDisarmed != null:
return pairingRequestedWhileDisarmed(_that.deviceName,_that.platform);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String deviceName,  DevicePlatform platform)  deviceRequestedPairing,required TResult Function( String pin,  String hostName,  DevicePlatform hostPlatform)  hostPinReceived,required TResult Function( String deviceId,  String certFingerprint)  pairingSucceeded,required TResult Function( String reason)  pairingRejected,required TResult Function( String deviceName,  DevicePlatform platform)  pairingRequestedWhileDisarmed,}) {final _that = this;
switch (_that) {
case PairingEvent_DeviceRequestedPairing():
return deviceRequestedPairing(_that.deviceName,_that.platform);case PairingEvent_HostPinReceived():
return hostPinReceived(_that.pin,_that.hostName,_that.hostPlatform);case PairingEvent_PairingSucceeded():
return pairingSucceeded(_that.deviceId,_that.certFingerprint);case PairingEvent_PairingRejected():
return pairingRejected(_that.reason);case PairingEvent_PairingRequestedWhileDisarmed():
return pairingRequestedWhileDisarmed(_that.deviceName,_that.platform);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String deviceName,  DevicePlatform platform)?  deviceRequestedPairing,TResult? Function( String pin,  String hostName,  DevicePlatform hostPlatform)?  hostPinReceived,TResult? Function( String deviceId,  String certFingerprint)?  pairingSucceeded,TResult? Function( String reason)?  pairingRejected,TResult? Function( String deviceName,  DevicePlatform platform)?  pairingRequestedWhileDisarmed,}) {final _that = this;
switch (_that) {
case PairingEvent_DeviceRequestedPairing() when deviceRequestedPairing != null:
return deviceRequestedPairing(_that.deviceName,_that.platform);case PairingEvent_HostPinReceived() when hostPinReceived != null:
return hostPinReceived(_that.pin,_that.hostName,_that.hostPlatform);case PairingEvent_PairingSucceeded() when pairingSucceeded != null:
return pairingSucceeded(_that.deviceId,_that.certFingerprint);case PairingEvent_PairingRejected() when pairingRejected != null:
return pairingRejected(_that.reason);case PairingEvent_PairingRequestedWhileDisarmed() when pairingRequestedWhileDisarmed != null:
return pairingRequestedWhileDisarmed(_that.deviceName,_that.platform);case _:
  return null;

}
}

}

/// @nodoc


class PairingEvent_DeviceRequestedPairing extends PairingEvent {
  const PairingEvent_DeviceRequestedPairing({required this.deviceName, required this.platform}): super._();
  

 final  String deviceName;
 final  DevicePlatform platform;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairingEvent_DeviceRequestedPairingCopyWith<PairingEvent_DeviceRequestedPairing> get copyWith => _$PairingEvent_DeviceRequestedPairingCopyWithImpl<PairingEvent_DeviceRequestedPairing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingEvent_DeviceRequestedPairing&&(identical(other.deviceName, deviceName) || other.deviceName == deviceName)&&(identical(other.platform, platform) || other.platform == platform));
}


@override
int get hashCode => Object.hash(runtimeType,deviceName,platform);

@override
String toString() {
  return 'PairingEvent.deviceRequestedPairing(deviceName: $deviceName, platform: $platform)';
}


}

/// @nodoc
abstract mixin class $PairingEvent_DeviceRequestedPairingCopyWith<$Res> implements $PairingEventCopyWith<$Res> {
  factory $PairingEvent_DeviceRequestedPairingCopyWith(PairingEvent_DeviceRequestedPairing value, $Res Function(PairingEvent_DeviceRequestedPairing) _then) = _$PairingEvent_DeviceRequestedPairingCopyWithImpl;
@useResult
$Res call({
 String deviceName, DevicePlatform platform
});




}
/// @nodoc
class _$PairingEvent_DeviceRequestedPairingCopyWithImpl<$Res>
    implements $PairingEvent_DeviceRequestedPairingCopyWith<$Res> {
  _$PairingEvent_DeviceRequestedPairingCopyWithImpl(this._self, this._then);

  final PairingEvent_DeviceRequestedPairing _self;
  final $Res Function(PairingEvent_DeviceRequestedPairing) _then;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceName = null,Object? platform = null,}) {
  return _then(PairingEvent_DeviceRequestedPairing(
deviceName: null == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as DevicePlatform,
  ));
}


}

/// @nodoc


class PairingEvent_HostPinReceived extends PairingEvent {
  const PairingEvent_HostPinReceived({required this.pin, required this.hostName, required this.hostPlatform}): super._();
  

 final  String pin;
 final  String hostName;
 final  DevicePlatform hostPlatform;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairingEvent_HostPinReceivedCopyWith<PairingEvent_HostPinReceived> get copyWith => _$PairingEvent_HostPinReceivedCopyWithImpl<PairingEvent_HostPinReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingEvent_HostPinReceived&&(identical(other.pin, pin) || other.pin == pin)&&(identical(other.hostName, hostName) || other.hostName == hostName)&&(identical(other.hostPlatform, hostPlatform) || other.hostPlatform == hostPlatform));
}


@override
int get hashCode => Object.hash(runtimeType,pin,hostName,hostPlatform);

@override
String toString() {
  return 'PairingEvent.hostPinReceived(pin: $pin, hostName: $hostName, hostPlatform: $hostPlatform)';
}


}

/// @nodoc
abstract mixin class $PairingEvent_HostPinReceivedCopyWith<$Res> implements $PairingEventCopyWith<$Res> {
  factory $PairingEvent_HostPinReceivedCopyWith(PairingEvent_HostPinReceived value, $Res Function(PairingEvent_HostPinReceived) _then) = _$PairingEvent_HostPinReceivedCopyWithImpl;
@useResult
$Res call({
 String pin, String hostName, DevicePlatform hostPlatform
});




}
/// @nodoc
class _$PairingEvent_HostPinReceivedCopyWithImpl<$Res>
    implements $PairingEvent_HostPinReceivedCopyWith<$Res> {
  _$PairingEvent_HostPinReceivedCopyWithImpl(this._self, this._then);

  final PairingEvent_HostPinReceived _self;
  final $Res Function(PairingEvent_HostPinReceived) _then;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pin = null,Object? hostName = null,Object? hostPlatform = null,}) {
  return _then(PairingEvent_HostPinReceived(
pin: null == pin ? _self.pin : pin // ignore: cast_nullable_to_non_nullable
as String,hostName: null == hostName ? _self.hostName : hostName // ignore: cast_nullable_to_non_nullable
as String,hostPlatform: null == hostPlatform ? _self.hostPlatform : hostPlatform // ignore: cast_nullable_to_non_nullable
as DevicePlatform,
  ));
}


}

/// @nodoc


class PairingEvent_PairingSucceeded extends PairingEvent {
  const PairingEvent_PairingSucceeded({required this.deviceId, required this.certFingerprint}): super._();
  

 final  String deviceId;
 final  String certFingerprint;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairingEvent_PairingSucceededCopyWith<PairingEvent_PairingSucceeded> get copyWith => _$PairingEvent_PairingSucceededCopyWithImpl<PairingEvent_PairingSucceeded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingEvent_PairingSucceeded&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.certFingerprint, certFingerprint) || other.certFingerprint == certFingerprint));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,certFingerprint);

@override
String toString() {
  return 'PairingEvent.pairingSucceeded(deviceId: $deviceId, certFingerprint: $certFingerprint)';
}


}

/// @nodoc
abstract mixin class $PairingEvent_PairingSucceededCopyWith<$Res> implements $PairingEventCopyWith<$Res> {
  factory $PairingEvent_PairingSucceededCopyWith(PairingEvent_PairingSucceeded value, $Res Function(PairingEvent_PairingSucceeded) _then) = _$PairingEvent_PairingSucceededCopyWithImpl;
@useResult
$Res call({
 String deviceId, String certFingerprint
});




}
/// @nodoc
class _$PairingEvent_PairingSucceededCopyWithImpl<$Res>
    implements $PairingEvent_PairingSucceededCopyWith<$Res> {
  _$PairingEvent_PairingSucceededCopyWithImpl(this._self, this._then);

  final PairingEvent_PairingSucceeded _self;
  final $Res Function(PairingEvent_PairingSucceeded) _then;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? certFingerprint = null,}) {
  return _then(PairingEvent_PairingSucceeded(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,certFingerprint: null == certFingerprint ? _self.certFingerprint : certFingerprint // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PairingEvent_PairingRejected extends PairingEvent {
  const PairingEvent_PairingRejected({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairingEvent_PairingRejectedCopyWith<PairingEvent_PairingRejected> get copyWith => _$PairingEvent_PairingRejectedCopyWithImpl<PairingEvent_PairingRejected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingEvent_PairingRejected&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'PairingEvent.pairingRejected(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $PairingEvent_PairingRejectedCopyWith<$Res> implements $PairingEventCopyWith<$Res> {
  factory $PairingEvent_PairingRejectedCopyWith(PairingEvent_PairingRejected value, $Res Function(PairingEvent_PairingRejected) _then) = _$PairingEvent_PairingRejectedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$PairingEvent_PairingRejectedCopyWithImpl<$Res>
    implements $PairingEvent_PairingRejectedCopyWith<$Res> {
  _$PairingEvent_PairingRejectedCopyWithImpl(this._self, this._then);

  final PairingEvent_PairingRejected _self;
  final $Res Function(PairingEvent_PairingRejected) _then;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(PairingEvent_PairingRejected(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PairingEvent_PairingRequestedWhileDisarmed extends PairingEvent {
  const PairingEvent_PairingRequestedWhileDisarmed({required this.deviceName, required this.platform}): super._();
  

 final  String deviceName;
 final  DevicePlatform platform;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PairingEvent_PairingRequestedWhileDisarmedCopyWith<PairingEvent_PairingRequestedWhileDisarmed> get copyWith => _$PairingEvent_PairingRequestedWhileDisarmedCopyWithImpl<PairingEvent_PairingRequestedWhileDisarmed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairingEvent_PairingRequestedWhileDisarmed&&(identical(other.deviceName, deviceName) || other.deviceName == deviceName)&&(identical(other.platform, platform) || other.platform == platform));
}


@override
int get hashCode => Object.hash(runtimeType,deviceName,platform);

@override
String toString() {
  return 'PairingEvent.pairingRequestedWhileDisarmed(deviceName: $deviceName, platform: $platform)';
}


}

/// @nodoc
abstract mixin class $PairingEvent_PairingRequestedWhileDisarmedCopyWith<$Res> implements $PairingEventCopyWith<$Res> {
  factory $PairingEvent_PairingRequestedWhileDisarmedCopyWith(PairingEvent_PairingRequestedWhileDisarmed value, $Res Function(PairingEvent_PairingRequestedWhileDisarmed) _then) = _$PairingEvent_PairingRequestedWhileDisarmedCopyWithImpl;
@useResult
$Res call({
 String deviceName, DevicePlatform platform
});




}
/// @nodoc
class _$PairingEvent_PairingRequestedWhileDisarmedCopyWithImpl<$Res>
    implements $PairingEvent_PairingRequestedWhileDisarmedCopyWith<$Res> {
  _$PairingEvent_PairingRequestedWhileDisarmedCopyWithImpl(this._self, this._then);

  final PairingEvent_PairingRequestedWhileDisarmed _self;
  final $Res Function(PairingEvent_PairingRequestedWhileDisarmed) _then;

/// Create a copy of PairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceName = null,Object? platform = null,}) {
  return _then(PairingEvent_PairingRequestedWhileDisarmed(
deviceName: null == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as DevicePlatform,
  ));
}


}

// dart format on
