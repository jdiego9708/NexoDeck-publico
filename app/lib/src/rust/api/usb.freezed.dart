// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'usb.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UsbEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'UsbEvent()';
}


}

/// @nodoc
class $UsbEventCopyWith<$Res>  {
$UsbEventCopyWith(UsbEvent _, $Res Function(UsbEvent) __);
}


/// Adds pattern-matching-related methods to [UsbEvent].
extension UsbEventPatterns on UsbEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UsbEvent_PhoneDetected value)?  phoneDetected,TResult Function( UsbEvent_DriverBlocked value)?  driverBlocked,TResult Function( UsbEvent_AccessoryModeStarted value)?  accessoryModeStarted,TResult Function( UsbEvent_AccessoryConnected value)?  accessoryConnected,TResult Function( UsbEvent_AccessoryDisconnected value)?  accessoryDisconnected,TResult Function( UsbEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UsbEvent_PhoneDetected() when phoneDetected != null:
return phoneDetected(_that);case UsbEvent_DriverBlocked() when driverBlocked != null:
return driverBlocked(_that);case UsbEvent_AccessoryModeStarted() when accessoryModeStarted != null:
return accessoryModeStarted(_that);case UsbEvent_AccessoryConnected() when accessoryConnected != null:
return accessoryConnected(_that);case UsbEvent_AccessoryDisconnected() when accessoryDisconnected != null:
return accessoryDisconnected(_that);case UsbEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UsbEvent_PhoneDetected value)  phoneDetected,required TResult Function( UsbEvent_DriverBlocked value)  driverBlocked,required TResult Function( UsbEvent_AccessoryModeStarted value)  accessoryModeStarted,required TResult Function( UsbEvent_AccessoryConnected value)  accessoryConnected,required TResult Function( UsbEvent_AccessoryDisconnected value)  accessoryDisconnected,required TResult Function( UsbEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case UsbEvent_PhoneDetected():
return phoneDetected(_that);case UsbEvent_DriverBlocked():
return driverBlocked(_that);case UsbEvent_AccessoryModeStarted():
return accessoryModeStarted(_that);case UsbEvent_AccessoryConnected():
return accessoryConnected(_that);case UsbEvent_AccessoryDisconnected():
return accessoryDisconnected(_that);case UsbEvent_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UsbEvent_PhoneDetected value)?  phoneDetected,TResult? Function( UsbEvent_DriverBlocked value)?  driverBlocked,TResult? Function( UsbEvent_AccessoryModeStarted value)?  accessoryModeStarted,TResult? Function( UsbEvent_AccessoryConnected value)?  accessoryConnected,TResult? Function( UsbEvent_AccessoryDisconnected value)?  accessoryDisconnected,TResult? Function( UsbEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case UsbEvent_PhoneDetected() when phoneDetected != null:
return phoneDetected(_that);case UsbEvent_DriverBlocked() when driverBlocked != null:
return driverBlocked(_that);case UsbEvent_AccessoryModeStarted() when accessoryModeStarted != null:
return accessoryModeStarted(_that);case UsbEvent_AccessoryConnected() when accessoryConnected != null:
return accessoryConnected(_that);case UsbEvent_AccessoryDisconnected() when accessoryDisconnected != null:
return accessoryDisconnected(_that);case UsbEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int vendorId,  int productId,  String? product)?  phoneDetected,TResult Function( int vendorId,  int productId,  String? driver)?  driverBlocked,TResult Function()?  accessoryModeStarted,TResult Function()?  accessoryConnected,TResult Function()?  accessoryDisconnected,TResult Function( String detail)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UsbEvent_PhoneDetected() when phoneDetected != null:
return phoneDetected(_that.vendorId,_that.productId,_that.product);case UsbEvent_DriverBlocked() when driverBlocked != null:
return driverBlocked(_that.vendorId,_that.productId,_that.driver);case UsbEvent_AccessoryModeStarted() when accessoryModeStarted != null:
return accessoryModeStarted();case UsbEvent_AccessoryConnected() when accessoryConnected != null:
return accessoryConnected();case UsbEvent_AccessoryDisconnected() when accessoryDisconnected != null:
return accessoryDisconnected();case UsbEvent_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int vendorId,  int productId,  String? product)  phoneDetected,required TResult Function( int vendorId,  int productId,  String? driver)  driverBlocked,required TResult Function()  accessoryModeStarted,required TResult Function()  accessoryConnected,required TResult Function()  accessoryDisconnected,required TResult Function( String detail)  failed,}) {final _that = this;
switch (_that) {
case UsbEvent_PhoneDetected():
return phoneDetected(_that.vendorId,_that.productId,_that.product);case UsbEvent_DriverBlocked():
return driverBlocked(_that.vendorId,_that.productId,_that.driver);case UsbEvent_AccessoryModeStarted():
return accessoryModeStarted();case UsbEvent_AccessoryConnected():
return accessoryConnected();case UsbEvent_AccessoryDisconnected():
return accessoryDisconnected();case UsbEvent_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int vendorId,  int productId,  String? product)?  phoneDetected,TResult? Function( int vendorId,  int productId,  String? driver)?  driverBlocked,TResult? Function()?  accessoryModeStarted,TResult? Function()?  accessoryConnected,TResult? Function()?  accessoryDisconnected,TResult? Function( String detail)?  failed,}) {final _that = this;
switch (_that) {
case UsbEvent_PhoneDetected() when phoneDetected != null:
return phoneDetected(_that.vendorId,_that.productId,_that.product);case UsbEvent_DriverBlocked() when driverBlocked != null:
return driverBlocked(_that.vendorId,_that.productId,_that.driver);case UsbEvent_AccessoryModeStarted() when accessoryModeStarted != null:
return accessoryModeStarted();case UsbEvent_AccessoryConnected() when accessoryConnected != null:
return accessoryConnected();case UsbEvent_AccessoryDisconnected() when accessoryDisconnected != null:
return accessoryDisconnected();case UsbEvent_Failed() when failed != null:
return failed(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class UsbEvent_PhoneDetected extends UsbEvent {
  const UsbEvent_PhoneDetected({required this.vendorId, required this.productId, this.product}): super._();
  

 final  int vendorId;
 final  int productId;
 final  String? product;

/// Create a copy of UsbEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbEvent_PhoneDetectedCopyWith<UsbEvent_PhoneDetected> get copyWith => _$UsbEvent_PhoneDetectedCopyWithImpl<UsbEvent_PhoneDetected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent_PhoneDetected&&(identical(other.vendorId, vendorId) || other.vendorId == vendorId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.product, product) || other.product == product));
}


@override
int get hashCode => Object.hash(runtimeType,vendorId,productId,product);

@override
String toString() {
  return 'UsbEvent.phoneDetected(vendorId: $vendorId, productId: $productId, product: $product)';
}


}

/// @nodoc
abstract mixin class $UsbEvent_PhoneDetectedCopyWith<$Res> implements $UsbEventCopyWith<$Res> {
  factory $UsbEvent_PhoneDetectedCopyWith(UsbEvent_PhoneDetected value, $Res Function(UsbEvent_PhoneDetected) _then) = _$UsbEvent_PhoneDetectedCopyWithImpl;
@useResult
$Res call({
 int vendorId, int productId, String? product
});




}
/// @nodoc
class _$UsbEvent_PhoneDetectedCopyWithImpl<$Res>
    implements $UsbEvent_PhoneDetectedCopyWith<$Res> {
  _$UsbEvent_PhoneDetectedCopyWithImpl(this._self, this._then);

  final UsbEvent_PhoneDetected _self;
  final $Res Function(UsbEvent_PhoneDetected) _then;

/// Create a copy of UsbEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? vendorId = null,Object? productId = null,Object? product = freezed,}) {
  return _then(UsbEvent_PhoneDetected(
vendorId: null == vendorId ? _self.vendorId : vendorId // ignore: cast_nullable_to_non_nullable
as int,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int,product: freezed == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class UsbEvent_DriverBlocked extends UsbEvent {
  const UsbEvent_DriverBlocked({required this.vendorId, required this.productId, this.driver}): super._();
  

 final  int vendorId;
 final  int productId;
 final  String? driver;

/// Create a copy of UsbEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbEvent_DriverBlockedCopyWith<UsbEvent_DriverBlocked> get copyWith => _$UsbEvent_DriverBlockedCopyWithImpl<UsbEvent_DriverBlocked>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent_DriverBlocked&&(identical(other.vendorId, vendorId) || other.vendorId == vendorId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.driver, driver) || other.driver == driver));
}


@override
int get hashCode => Object.hash(runtimeType,vendorId,productId,driver);

@override
String toString() {
  return 'UsbEvent.driverBlocked(vendorId: $vendorId, productId: $productId, driver: $driver)';
}


}

/// @nodoc
abstract mixin class $UsbEvent_DriverBlockedCopyWith<$Res> implements $UsbEventCopyWith<$Res> {
  factory $UsbEvent_DriverBlockedCopyWith(UsbEvent_DriverBlocked value, $Res Function(UsbEvent_DriverBlocked) _then) = _$UsbEvent_DriverBlockedCopyWithImpl;
@useResult
$Res call({
 int vendorId, int productId, String? driver
});




}
/// @nodoc
class _$UsbEvent_DriverBlockedCopyWithImpl<$Res>
    implements $UsbEvent_DriverBlockedCopyWith<$Res> {
  _$UsbEvent_DriverBlockedCopyWithImpl(this._self, this._then);

  final UsbEvent_DriverBlocked _self;
  final $Res Function(UsbEvent_DriverBlocked) _then;

/// Create a copy of UsbEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? vendorId = null,Object? productId = null,Object? driver = freezed,}) {
  return _then(UsbEvent_DriverBlocked(
vendorId: null == vendorId ? _self.vendorId : vendorId // ignore: cast_nullable_to_non_nullable
as int,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as int,driver: freezed == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class UsbEvent_AccessoryModeStarted extends UsbEvent {
  const UsbEvent_AccessoryModeStarted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent_AccessoryModeStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'UsbEvent.accessoryModeStarted()';
}


}




/// @nodoc


class UsbEvent_AccessoryConnected extends UsbEvent {
  const UsbEvent_AccessoryConnected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent_AccessoryConnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'UsbEvent.accessoryConnected()';
}


}




/// @nodoc


class UsbEvent_AccessoryDisconnected extends UsbEvent {
  const UsbEvent_AccessoryDisconnected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent_AccessoryDisconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'UsbEvent.accessoryDisconnected()';
}


}




/// @nodoc


class UsbEvent_Failed extends UsbEvent {
  const UsbEvent_Failed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of UsbEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsbEvent_FailedCopyWith<UsbEvent_Failed> get copyWith => _$UsbEvent_FailedCopyWithImpl<UsbEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UsbEvent_Failed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'UsbEvent.failed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $UsbEvent_FailedCopyWith<$Res> implements $UsbEventCopyWith<$Res> {
  factory $UsbEvent_FailedCopyWith(UsbEvent_Failed value, $Res Function(UsbEvent_Failed) _then) = _$UsbEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$UsbEvent_FailedCopyWithImpl<$Res>
    implements $UsbEvent_FailedCopyWith<$Res> {
  _$UsbEvent_FailedCopyWithImpl(this._self, this._then);

  final UsbEvent_Failed _self;
  final $Res Function(UsbEvent_Failed) _then;

/// Create a copy of UsbEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(UsbEvent_Failed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
