// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'relay.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RelayStatus {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RelayStatus()';
}


}

/// @nodoc
class $RelayStatusCopyWith<$Res>  {
$RelayStatusCopyWith(RelayStatus _, $Res Function(RelayStatus) __);
}


/// Adds pattern-matching-related methods to [RelayStatus].
extension RelayStatusPatterns on RelayStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RelayStatus_Parked value)?  parked,TResult Function( RelayStatus_Matched value)?  matched,TResult Function( RelayStatus_Failed value)?  failed,TResult Function( RelayStatus_Stopped value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RelayStatus_Parked() when parked != null:
return parked(_that);case RelayStatus_Matched() when matched != null:
return matched(_that);case RelayStatus_Failed() when failed != null:
return failed(_that);case RelayStatus_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RelayStatus_Parked value)  parked,required TResult Function( RelayStatus_Matched value)  matched,required TResult Function( RelayStatus_Failed value)  failed,required TResult Function( RelayStatus_Stopped value)  stopped,}){
final _that = this;
switch (_that) {
case RelayStatus_Parked():
return parked(_that);case RelayStatus_Matched():
return matched(_that);case RelayStatus_Failed():
return failed(_that);case RelayStatus_Stopped():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RelayStatus_Parked value)?  parked,TResult? Function( RelayStatus_Matched value)?  matched,TResult? Function( RelayStatus_Failed value)?  failed,TResult? Function( RelayStatus_Stopped value)?  stopped,}){
final _that = this;
switch (_that) {
case RelayStatus_Parked() when parked != null:
return parked(_that);case RelayStatus_Matched() when matched != null:
return matched(_that);case RelayStatus_Failed() when failed != null:
return failed(_that);case RelayStatus_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  parked,TResult Function()?  matched,TResult Function( String reason)?  failed,TResult Function()?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RelayStatus_Parked() when parked != null:
return parked();case RelayStatus_Matched() when matched != null:
return matched();case RelayStatus_Failed() when failed != null:
return failed(_that.reason);case RelayStatus_Stopped() when stopped != null:
return stopped();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  parked,required TResult Function()  matched,required TResult Function( String reason)  failed,required TResult Function()  stopped,}) {final _that = this;
switch (_that) {
case RelayStatus_Parked():
return parked();case RelayStatus_Matched():
return matched();case RelayStatus_Failed():
return failed(_that.reason);case RelayStatus_Stopped():
return stopped();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  parked,TResult? Function()?  matched,TResult? Function( String reason)?  failed,TResult? Function()?  stopped,}) {final _that = this;
switch (_that) {
case RelayStatus_Parked() when parked != null:
return parked();case RelayStatus_Matched() when matched != null:
return matched();case RelayStatus_Failed() when failed != null:
return failed(_that.reason);case RelayStatus_Stopped() when stopped != null:
return stopped();case _:
  return null;

}
}

}

/// @nodoc


class RelayStatus_Parked extends RelayStatus {
  const RelayStatus_Parked(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayStatus_Parked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RelayStatus.parked()';
}


}




/// @nodoc


class RelayStatus_Matched extends RelayStatus {
  const RelayStatus_Matched(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayStatus_Matched);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RelayStatus.matched()';
}


}




/// @nodoc


class RelayStatus_Failed extends RelayStatus {
  const RelayStatus_Failed({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of RelayStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RelayStatus_FailedCopyWith<RelayStatus_Failed> get copyWith => _$RelayStatus_FailedCopyWithImpl<RelayStatus_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayStatus_Failed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RelayStatus.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RelayStatus_FailedCopyWith<$Res> implements $RelayStatusCopyWith<$Res> {
  factory $RelayStatus_FailedCopyWith(RelayStatus_Failed value, $Res Function(RelayStatus_Failed) _then) = _$RelayStatus_FailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$RelayStatus_FailedCopyWithImpl<$Res>
    implements $RelayStatus_FailedCopyWith<$Res> {
  _$RelayStatus_FailedCopyWithImpl(this._self, this._then);

  final RelayStatus_Failed _self;
  final $Res Function(RelayStatus_Failed) _then;

/// Create a copy of RelayStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RelayStatus_Failed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RelayStatus_Stopped extends RelayStatus {
  const RelayStatus_Stopped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayStatus_Stopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RelayStatus.stopped()';
}


}




// dart format on
